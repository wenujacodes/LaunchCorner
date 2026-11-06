import Foundation
import SwiftUI
import Combine
import ServiceManagement

// Observable store that persists AppConfig to UserDefaults
@MainActor
class ConfigStore: ObservableObject {
    let configDidChange = PassthroughSubject<AppConfig, Never>()
    
    @Published var config: AppConfig {
        didSet {
            save()
            configDidChange.send(config)
        }
    }
    
    @Published var isLaunchAtLoginEnabled: Bool = false {
        didSet {
            setLaunchAtLogin(isLaunchAtLoginEnabled)
        }
    }
    
    private let userDefaultsKey = "LaunchCornerAppConfig"
    private let corruptBackupKey = "LaunchCornerAppConfig.corruptBackup"
    private let launchAtLoginDefaultKey = "LaunchCornerLaunchAtLoginDefaultApplied"
    
    init() {
        let isFreshInstall = UserDefaults.standard.data(forKey: userDefaultsKey) == nil
            && UserDefaults.standard.data(forKey: "NookAppConfig") == nil
        
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            self.config = decoded
        } else {
            // Unparseable primary blob: stash it for forensics instead of
            // silently losing it (e.g. hand-edited or downgraded configs).
            if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
                UserDefaults.standard.set(data, forKey: corruptBackupKey)
            }
            if let oldData = UserDefaults.standard.data(forKey: "NookAppConfig"),
                      let decoded = try? JSONDecoder().decode(AppConfig.self, from: oldData) {
                self.config = decoded
            } else {
                self.config = .default
            }
        }
        
        // Launch at Login is on by default for new installs. Applied once, so turning it off sticks.
        if !UserDefaults.standard.bool(forKey: launchAtLoginDefaultKey) {
            UserDefaults.standard.set(true, forKey: launchAtLoginDefaultKey)
            if isFreshInstall {
                setLaunchAtLogin(true)
            }
        }
        
        self.isLaunchAtLoginEnabled = checkLaunchAtLogin()
    }
    
    private func checkLaunchAtLogin() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
    
    func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to toggle Launch at Login: \(error.localizedDescription)")
            }
        }
    }
    
    func save() {
        if let encoded = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            // A good save retires any stale forensics backup.
            UserDefaults.standard.removeObject(forKey: corruptBackupKey)
        }
    }
    
    func resetAllCorners() {
        config.defaultConfig = .empty
        config.screenConfigs = [:]
        save()
    }
    
    // Convenience accessors
    func cornerConfig(forScreenID screenID: String?) -> ScreenCornerConfig {
        guard let screenID = screenID else { return config.defaultConfig }
        switch config.monitorMode {
        case .allScreens:
            return config.defaultConfig
        case .specificScreen(let targetScreenID):
            if screenID == targetScreenID {
                return config.screenConfigs[screenID] ?? config.defaultConfig
            } else {
                return .empty
            }
        }
    }
    
    func setCornerAction(_ action: CornerAction, for corner: Corner, screenID: String?) {
        if let screenID = screenID, case .specificScreen(let targetID) = config.monitorMode, screenID == targetID {
            var screenConfig = config.screenConfigs[screenID] ?? config.defaultConfig
            screenConfig.setAction(action, for: corner)
            config.screenConfigs[screenID] = screenConfig
        } else {
            config.defaultConfig.setAction(action, for: corner)
        }
    }
}
