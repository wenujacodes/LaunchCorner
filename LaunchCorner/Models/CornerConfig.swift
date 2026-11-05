import Foundation
import AppKit

// The 4 screen corners
enum Corner: String, Codable, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
    
    var symbolName: String {
        switch self {
        case .topLeft: return "arrow.up.left"
        case .topRight: return "arrow.up.right"
        case .bottomLeft: return "arrow.down.left"
        case .bottomRight: return "arrow.down.right"
        }
    }
}

// What action to perform when a corner is triggered
enum CornerAction: Codable, Equatable {
    case none
    case launchApp(bundlePath: String, appName: String)
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .launchApp(_, let appName): return appName
        }
    }
    
    var isConfigured: Bool {
        if case .none = self { return false }
        return true
    }
    
    func appIcon() -> NSImage? {
        switch self {
        case .none: return nil
        case .launchApp(let bundlePath, _):
            return NSWorkspace.shared.icon(forFile: bundlePath)
        }
    }
}

// Config for one screen's 4 corners
struct ScreenCornerConfig: Codable, Equatable {
    var corners: [String: CornerAction]
    
    static var empty: ScreenCornerConfig {
        ScreenCornerConfig(corners: [
            Corner.topLeft.rawValue: .none,
            Corner.topRight.rawValue: .none,
            Corner.bottomLeft.rawValue: .none,
            Corner.bottomRight.rawValue: .none
        ])
    }
    
    func action(for corner: Corner) -> CornerAction {
        return corners[corner.rawValue] ?? .none
    }
    
    mutating func setAction(_ action: CornerAction, for corner: Corner) {
        corners[corner.rawValue] = action
    }
}

// Which monitors to watch
enum MonitorMode: Codable, Equatable {
    case allScreens
    case specificScreen(String)
}

// Top-level app configuration
struct AppConfig: Codable, Equatable {
    var screenConfigs: [String: ScreenCornerConfig]
    var defaultConfig: ScreenCornerConfig
    var dwellTime: Double
    var hitZoneSize: Double
    var isActive: Bool
    var monitorMode: MonitorMode
    var autoCheckUpdates: Bool
    
    static var `default`: AppConfig {
        AppConfig(
            screenConfigs: [:],
            defaultConfig: .empty,
            dwellTime: 0.15,
            hitZoneSize: 15.0,
            isActive: true,
            monitorMode: .allScreens,
            autoCheckUpdates: true
        )
    }
    
    enum CodingKeys: String, CodingKey {
        case screenConfigs, defaultConfig, dwellTime, hitZoneSize, isActive, monitorMode, autoCheckUpdates
    }
    
    init(screenConfigs: [String: ScreenCornerConfig], defaultConfig: ScreenCornerConfig, dwellTime: Double, hitZoneSize: Double, isActive: Bool, monitorMode: MonitorMode, autoCheckUpdates: Bool = true) {
        self.screenConfigs = screenConfigs
        self.defaultConfig = defaultConfig
        self.dwellTime = dwellTime
        self.hitZoneSize = hitZoneSize
        self.isActive = isActive
        self.monitorMode = monitorMode
        self.autoCheckUpdates = autoCheckUpdates
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        screenConfigs = try container.decodeIfPresent([String: ScreenCornerConfig].self, forKey: .screenConfigs) ?? [:]
        defaultConfig = try container.decodeIfPresent(ScreenCornerConfig.self, forKey: .defaultConfig) ?? .empty
        dwellTime = try container.decodeIfPresent(Double.self, forKey: .dwellTime) ?? 0.15
        hitZoneSize = try container.decodeIfPresent(Double.self, forKey: .hitZoneSize) ?? 15.0
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        monitorMode = try container.decodeIfPresent(MonitorMode.self, forKey: .monitorMode) ?? .allScreens
        autoCheckUpdates = try container.decodeIfPresent(Bool.self, forKey: .autoCheckUpdates) ?? true
    }
}
