import SwiftUI
import AppKit
import ServiceManagement

@MainActor
class AppState: ObservableObject {
    let configStore = ConfigStore()
    let permissionManager = PermissionManager()
    lazy var updateManager: UpdateManager = {
        UpdateManager()
    }()
    lazy var engine: CornerDetectionEngine = {
        CornerDetectionEngine(configStore: configStore)
    }()
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var appState: AppState?
    var openWindowHandler: (() -> Void)?
    
    /// Set when macOS opened the app at login. Used once, for the first window appearance.
    var shouldStartHidden = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        if wasLaunchedAtLogin() {
            shouldStartHidden = true
            // No Dock icon while starting in the background
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// True when macOS started the app at login, false when the user opened it.
    private func wasLaunchedAtLogin() -> Bool {
        // 1. The launch event is marked as a login-item launch
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem) {
            return true
        }

        // 2. Fallback: Launch at Login is on and the user logged in moments ago
        guard SMAppService.mainApp.status == .enabled,
              let loginDate = consoleLoginDate() else { return false }
        return Date().timeIntervalSince(loginDate) < 120
    }

    /// When the current user logged in to this Mac's screen (from the system login records).
    private func consoleLoginDate() -> Date? {
        let userName = NSUserName()
        var latest: Date?
        setutxent()
        defer { endutxent() }
        while let entry = getutxent() {
            guard entry.pointee.ut_type == USER_PROCESS else { continue }
            let user = withUnsafeBytes(of: entry.pointee.ut_user) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let line = withUnsafeBytes(of: entry.pointee.ut_line) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            guard user == userName, line == "console" else { continue }
            let date = Date(timeIntervalSince1970: TimeInterval(entry.pointee.ut_tv.tv_sec))
            if latest == nil || date > latest! { latest = date }
        }
        return latest
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }
    
    @objc private func handleWindowWillClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let closedWindow = notification.object as? NSWindow else { return }
            
            // Ignore sheets, popovers, or child windows
            if closedWindow.isSheet || closedWindow.sheetParent != nil || closedWindow.className.contains("Popover") {
                return
            }
            
            // Defer slightly so SwiftUI finishes processing window state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self, let configStore = self.appState?.configStore else { return }
                
                let hasVisibleMainWindow = NSApp.windows.contains { win in
                    win.isVisible && !win.isSheet && win.sheetParent == nil && win.level == .normal
                }
                
                if !hasVisibleMainWindow {
                    // Hide from Dock (.accessory) and keep running in background
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }
    
    /// Hides the main window without closing it, so reopening the app shows it again.
    func hideMainWindowForBackgroundLaunch() {
        for window in NSApp.windows where !window.isSheet && window.sheetParent == nil && window.level == .normal {
            window.orderOut(nil)
        }
        NSApp.setActivationPolicy(.accessory)
    }
    
    func showMainWindow() {
        Task { @MainActor [weak self] in
            NSApp.setActivationPolicy(.regular)
            
            // 1. Try visible main windows
            if let window = NSApp.windows.first(where: { win in
                win.isVisible && !win.isSheet && win.sheetParent == nil && win.level == .normal
            }) {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            
            // 2. Try non-visible main windows
            if let window = NSApp.windows.first(where: { win in
                !win.isSheet && win.sheetParent == nil && win.level == .normal
            }) {
                window.setIsVisible(true)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            
            // 3. Fallback: Re-open main window via SwiftUI openWindow
            self?.openWindowHandler?()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApp.windows.first(where: { !$0.isSheet && $0.sheetParent == nil }) {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }
}

struct MainViewContainer: View {
    @Environment(\.openWindow) private var openWindow
    let appDelegate: AppDelegate
    
    var body: some View {
        MainView()
            .onAppear {
                appDelegate.openWindowHandler = {
                    openWindow(id: "main-window")
                }
            }
    }
}

@main
struct LaunchCornerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup("LaunchCorner", id: "main-window") {
            mainContent
        }
        .windowResizability(.contentSize)
        .windowStyle(.automatic)
    }

    private var mainContent: some View {
        MainViewContainer(appDelegate: appDelegate)
            .environmentObject(appState.configStore)
            .environmentObject(appState.permissionManager)
            .environmentObject(appState.engine)
            .environmentObject(appState.updateManager)
            .onAppear {
                appDelegate.appState = appState

                // Start in the background only if setup is done; otherwise show onboarding.
                let startHidden = appDelegate.shouldStartHidden && appState.permissionManager.isAccessibilityGranted
                appDelegate.shouldStartHidden = false
                if !startHidden {
                    appDelegate.showMainWindow()
                }
                appState.permissionManager.startMonitoringPermission()

                if startHidden {
                    // Defer so the window's views finish their own setup first
                    DispatchQueue.main.async {
                        appDelegate.hideMainWindowForBackgroundLaunch()
                    }
                }
            }
    }
}
