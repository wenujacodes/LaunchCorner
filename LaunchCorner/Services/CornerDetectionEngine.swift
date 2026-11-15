import Foundation
import AppKit
import Combine

extension NSScreen {
    var displayID: String? {
        if let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            return String(number)
        }
        return nil
    }
}

private struct CachedScreenInfo {
    let screenID: String
    let frame: NSRect
}

@MainActor
class CornerDetectionEngine: ObservableObject {
    @Published var isActive: Bool = false
    @Published var lastTriggeredCorner: Corner? = nil
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var dwellTimer: DispatchSourceTimer?
    private var currentCorner: (corner: Corner, screenID: String)? = nil
    private var hasTriggeredForCurrentEntry: Bool = false
    private var cooldownActive: Bool = false
    
    private var cachedScreens: [CachedScreenInfo] = []
    private var combinedOuterBounds: NSRect = .zero
    
    private let configStore: ConfigStore
    private var cancellables = Set<AnyCancellable>()
    
    init(configStore: ConfigStore) {
        self.configStore = configStore
        
        configStore.$config
            .map { $0.isActive }
            .removeDuplicates()
            .sink { [weak self] isActive in
                if isActive {
                    self?.start()
                } else {
                    self?.stop()
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.refreshScreenCache()
            }
            .store(in: &cancellables)
    }
    
    func start() {
        guard !isActive else { return }
        refreshScreenCache()
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMoved(event: event)
        }
        
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMoved(event: event)
            return event
        }
        
        isActive = true
    }
    
    func stop() {
        guard isActive else { return }
        
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        
        cancelDwellTimer()
        isActive = false
    }
    
    private func refreshScreenCache() {
        var newCache: [CachedScreenInfo] = []
        var unionFrame: NSRect = .null
        
        for screen in NSScreen.screens {
            if let id = screen.displayID {
                newCache.append(CachedScreenInfo(screenID: id, frame: screen.frame))
                unionFrame = unionFrame.union(screen.frame)
            }
        }
        
        self.cachedScreens = newCache
        self.combinedOuterBounds = unionFrame
    }
    
    private func handleMouseMoved(event: NSEvent) {
        let location = NSEvent.mouseLocation
        
        if let detected = detectCorner(at: location) {
            if currentCorner?.corner != detected.corner || currentCorner?.screenID != detected.screenID {
                // Entered a brand new corner
                currentCorner = detected
                hasTriggeredForCurrentEntry = false
                cooldownActive = false
                startDwellTimer(for: detected.corner, screenID: detected.screenID)
            } else {
                // Mouse is still inside the SAME corner
                if !hasTriggeredForCurrentEntry && !cooldownActive && dwellTimer == nil {
                    startDwellTimer(for: detected.corner, screenID: detected.screenID)
                }
            }
        } else {
            // Mouse exited corner hit zone completely - reset triggers & cooldown immediately for instant re-trigger
            if currentCorner != nil {
                currentCorner = nil
                hasTriggeredForCurrentEntry = false
                cooldownActive = false
                cancelDwellTimer()
            }
        }
    }
    
    private func detectCorner(at point: NSPoint) -> (corner: Corner, screenID: String)? {
        let hitZone = configStore.config.hitZoneSize
        
        // Fast path: if mouse is in the safe inner area of all screens, skip corner checks immediately
        if !combinedOuterBounds.isNull &&
            point.x > combinedOuterBounds.minX + hitZone &&
            point.x < combinedOuterBounds.maxX - hitZone &&
            point.y > combinedOuterBounds.minY + hitZone &&
            point.y < combinedOuterBounds.maxY - hitZone {
            return nil
        }
        
        for screen in cachedScreens {
            switch configStore.config.monitorMode {
            case .allScreens:
                break
            case .specificScreen(let targetID):
                if screen.screenID != targetID { continue }
            }
            
            let frame = screen.frame
            
            // Corners take priority over edges (corner squares win ties).
            if point.x <= frame.minX + hitZone && point.y >= frame.maxY - hitZone {
                return (.topLeft, screen.screenID)
            } else if point.x >= frame.maxX - hitZone && point.y >= frame.maxY - hitZone {
                return (.topRight, screen.screenID)
            } else if point.x <= frame.minX + hitZone && point.y <= frame.minY + hitZone {
                return (.bottomLeft, screen.screenID)
            } else if point.x >= frame.maxX - hitZone && point.y <= frame.minY + hitZone {
                return (.bottomRight, screen.screenID)
            }
            // Edges: middle strip of each side, excluding the corner squares.
            let midX = point.x > frame.minX + hitZone && point.x < frame.maxX - hitZone
            let midY = point.y > frame.minY + hitZone && point.y < frame.maxY - hitZone
            if midX && point.y >= frame.maxY - hitZone {
                return (.topEdge, screen.screenID)
            } else if midY && point.x <= frame.minX + hitZone {
                return (.leftEdge, screen.screenID)
            } else if midY && point.x >= frame.maxX - hitZone {
                return (.rightEdge, screen.screenID)
            }
        }
        return nil
    }
    
    private func startDwellTimer(for corner: Corner, screenID: String) {
        cancelDwellTimer()
        
        let config = configStore.cornerConfig(forScreenID: screenID)
        let action = config.action(for: corner)
        
        guard action.isConfigured else { return }
        
        let dwellTime = configStore.config.dwellTime
        
        if dwellTime <= 0.01 {
            // Instant trigger for 0 ms dwell time
            triggerAction(for: corner, screenID: screenID)
        } else {
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
            timer.schedule(deadline: .now() + dwellTime)
            timer.setEventHandler { [weak self] in
                self?.triggerAction(for: corner, screenID: screenID)
            }
            timer.resume()
            self.dwellTimer = timer
        }
    }
    
    private func cancelDwellTimer() {
        dwellTimer?.cancel()
        dwellTimer = nil
    }
    
    private func triggerAction(for corner: Corner, screenID: String) {
        cancelDwellTimer()
        hasTriggeredForCurrentEntry = true
        
        let config = configStore.cornerConfig(forScreenID: screenID)
        let action = config.action(for: corner)
        
        guard action.isConfigured else { return }
        
        ActionExecutor.execute(action)
        lastTriggeredCorner = corner
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            if self?.lastTriggeredCorner == corner {
                self?.lastTriggeredCorner = nil
            }
        }
        
        startCooldown()
    }
    
    private func startCooldown() {
        cooldownActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.cooldownActive = false
        }
    }
}
