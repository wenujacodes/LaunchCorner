import Foundation
import AppKit
import ApplicationServices
import Combine

@MainActor
class PermissionManager: ObservableObject {
    @Published var isAccessibilityGranted: Bool = false
    
    private var checkTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isForceReset = false
    
    init() {
        checkPermission(prompt: false)
        
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.checkPermission(prompt: false)
            }
            .store(in: &cancellables)
    }
    
    func requestPermission() {
        isForceReset = false
        checkPermission(prompt: true)
    }
    
    func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    func resetPermission() {
        isForceReset = true
        isAccessibilityGranted = false
        stopMonitoringPermission()

        // Reset macOS TCC Accessibility permissions for LaunchCorner.
        // tccutil forks block for seconds: never on the main thread.
        let bundleIDs = Array(Set([Bundle.main.bundleIdentifier ?? "com.launchcorner.app", "com.launchcorner.app", "com.nook.hotcorner"]))
        DispatchQueue.global(qos: .utility).async {
            for id in bundleIDs {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                task.arguments = ["reset", "Accessibility", id]
                try? task.run()
                task.waitUntilExit()
            }
        }
    }
    
    func startMonitoringPermission() {
        stopMonitoringPermission()
        if checkPermission(prompt: false) {
            return
        }
        checkTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if self?.checkPermission(prompt: false) == true {
                    self?.stopMonitoringPermission()
                }
            }
        }
    }
    
    func stopMonitoringPermission() {
        checkTimer?.invalidate()
        checkTimer = nil
    }
    
    @discardableResult
    func checkPermission(prompt: Bool) -> Bool {
        if isForceReset {
            self.isAccessibilityGranted = false
            return false
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        let isGranted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if self.isAccessibilityGranted != isGranted {
            self.isAccessibilityGranted = isGranted
        }
        return isGranted
    }
}
