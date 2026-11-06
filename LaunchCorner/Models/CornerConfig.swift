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
enum CornerAction: Equatable {
    case none
    case launchApp(bundlePath: String, appName: String)
    case quickLink(name: String, url: String, openWithBundleID: String?)
    case shellCommand(command: String, shell: String)
    case script(language: ScriptLanguage, path: String, description: String)
    case windowSnap(position: SnapPosition)
    case systemAction(SystemAction)
    case screenshot(kind: ScreenshotKind, destination: ScreenshotDestination, directory: String)

    var displayName: String {
        switch self {
        case .none: return "None"
        case .launchApp(_, let appName): return appName
        case .quickLink(let name, let url, _): return name.isEmpty ? url : name
        case .shellCommand: return "Shell Command"
        case .script(let language, let path, _): return "\(language.displayName): \((path as NSString).lastPathComponent)"
        case .windowSnap(let position): return "Snap \(position.displayName)"
        case .systemAction(let action): return action.displayName
        case .screenshot(let kind, let destination, _): return "\(kind.displayName) → \(destination.displayName)"
        }
    }

    /// Secondary line for the config sheet preview.
    var detailText: String {
        switch self {
        case .none: return ""
        case .launchApp(let bundlePath, _): return bundlePath
        case .quickLink(_, let url, _): return url
        case .shellCommand(let command, let shell):
            return "\(shell): \(command)".trimmingCharacters(in: .whitespaces)
        case .script(_, let path, let description):
            return description.isEmpty ? path : description
        case .windowSnap(let position): return position.detailText
        case .systemAction(let action): return action.detailText
        case .screenshot(let kind, let destination, let directory):
            return destination == .clipboard ? "\(kind.displayName) to Clipboard" : "\(kind.displayName) to \(directory)"
        }
    }

    /// SF Symbol for the corner dot glyph (launchApp uses its app icon instead).
    var symbolName: String {
        switch self {
        case .none: return "plus"
        case .launchApp: return "app.dashed"
        case .quickLink: return "link"
        case .shellCommand: return "terminal"
        case .script(let language, _, _): return language.symbolName
        case .windowSnap(let position): return position.symbolName
        case .systemAction(let action): return action.symbolName
        case .screenshot: return "camera.viewfinder"
        }
    }

    var isConfigured: Bool {
        if case .none = self { return false }
        // Treat empty payloads as unconfigured so stale entries never fire.
        // (shell falls back to /bin/zsh at runtime, so only the command gates.)
        switch self {
        case .launchApp(let bundlePath, _):
            return !bundlePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .quickLink(_, let url, _): return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .shellCommand(let command, _):
            return !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .script(_, let path, _): return !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return true
        }
    }

    func appIcon() -> NSImage? {
        switch self {
        case .none: return nil
        case .launchApp(let bundlePath, _):
            return NSWorkspace.shared.icon(forFile: bundlePath)
        default: return nil
        }
    }
}

// MARK: - Action payload types

enum ScriptLanguage: String, Codable, CaseIterable, Identifiable {
    case bash, appleScript, python, javaScript, typeScript, go, ruby, csharp
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bash: return "Bash"
        case .appleScript: return "AppleScript"
        case .python: return "Python"
        case .javaScript: return "JavaScript"
        case .typeScript: return "TypeScript"
        case .go: return "Go"
        case .ruby: return "Ruby"
        case .csharp: return "C#"
        }
    }

    var symbolName: String {
        switch self {
        case .appleScript: return "applescript"
        case .python: return "ellipsis.curlybraces"
        default: return "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Candidate interpreter executables, in preference order.
    var interpreterCandidates: [String] {
        switch self {
        case .bash: return ["/bin/bash"]
        case .appleScript: return ["/usr/bin/osascript"]
        case .python: return ["/usr/bin/python3", "/opt/homebrew/bin/python3"]
        case .javaScript: return ["/opt/homebrew/bin/node", "/usr/local/bin/node"]
        case .typeScript: return ["/opt/homebrew/bin/tsx", "/opt/homebrew/bin/ts-node", "/opt/homebrew/bin/deno", "/usr/local/bin/ts-node"]
        case .go: return ["/opt/homebrew/bin/go", "/usr/local/go/bin/go"]
        case .ruby: return ["/usr/bin/ruby", "/opt/homebrew/bin/ruby"]
        case .csharp: return ["/opt/homebrew/bin/dotnet-script", "/usr/local/bin/dotnet-script"]
        }
    }
}

enum SnapPosition: String, Codable, CaseIterable, Identifiable {
    case top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .top: return "Top Half"
        case .bottom: return "Bottom Half"
        case .left: return "Left Half"
        case .right: return "Right Half"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }

    var detailText: String { "Move front window to \(displayName.lowercased())" }

    var symbolName: String {
        switch self {
        case .top: return "rectangle.tophalf.filled"
        case .bottom: return "rectangle.bottomhalf.filled"
        case .left: return "rectangle.lefthalf.filled"
        case .right: return "rectangle.righthalf.filled"
        case .topLeft: return "arrow.up.left.square"
        case .topRight: return "arrow.up.right.square"
        case .bottomLeft: return "arrow.down.left.square"
        case .bottomRight: return "arrow.down.right.square"
        }
    }
}

enum SystemAction: String, Codable, CaseIterable, Identifiable {
    case spotlight, mediaPlayPause, mediaNext, mediaPrevious
    case toggleAppearance, startScreenSaver, lockScreen, sleepDisplay
    case missionControl, appExpose, showDesktop
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spotlight: return "Spotlight"
        case .mediaPlayPause: return "Play / Pause"
        case .mediaNext: return "Next Track"
        case .mediaPrevious: return "Previous Track"
        case .toggleAppearance: return "Toggle Light / Dark"
        case .startScreenSaver: return "Start Screen Saver"
        case .lockScreen: return "Lock Screen"
        case .sleepDisplay: return "Sleep Display"
        case .missionControl: return "Mission Control"
        case .appExpose: return "Application Windows"
        case .showDesktop: return "Show Desktop"
        }
    }

    var detailText: String {
        switch self {
        case .spotlight: return "Opens Spotlight search (⌘Space)"
        case .mediaPlayPause: return "Toggles system-wide playback"
        case .mediaNext: return "Skips to the next track"
        case .mediaPrevious: return "Goes back to the previous track"
        case .toggleAppearance: return "Switches between light and dark mode"
        case .startScreenSaver: return "Starts the screen saver"
        case .lockScreen: return "Locks the screen (⌃⌘Q)"
        case .sleepDisplay: return "Puts displays to sleep immediately"
        case .missionControl: return "Opens Mission Control (⌃↑)"
        case .appExpose: return "Shows all windows of the front app (⌃↓)"
        case .showDesktop: return "Shows the desktop (F11)"
        }
    }

    var symbolName: String {
        switch self {
        case .spotlight: return "magnifyingglass"
        case .mediaPlayPause: return "playpause.fill"
        case .mediaNext: return "forward.fill"
        case .mediaPrevious: return "backward.fill"
        case .toggleAppearance: return "circle.lefthalf.fill"
        case .startScreenSaver: return "clock.fill"
        case .lockScreen: return "lock.fill"
        case .sleepDisplay: return "moon.fill"
        case .missionControl: return "square.grid.3x3"
        case .appExpose: return "square.on.square"
        case .showDesktop: return "macwindow"
        }
    }
}

enum ScreenshotKind: String, Codable, CaseIterable, Identifiable {
    case full, selection, window
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .full: return "Fullscreen"
        case .selection: return "Selection"
        case .window: return "Window"
        }
    }
}

enum ScreenshotDestination: String, Codable, CaseIterable, Identifiable {
    case file, clipboard
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .file: return "Save to File"
        case .clipboard: return "Copy to Clipboard"
        }
    }
}

// MARK: - CornerAction Codable (tolerant reader)
//
// Wire format keeps the original single-key style, so configs saved by older
// builds (`{"launchApp": {...}}`, `{"none": {}}`) decode unchanged. Unknown
// keys degrade to `.none` instead of dropping the whole config.
private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
    init?(intValue: Int) { return nil }
}

extension CornerAction: Codable {
    private enum Key: String, CodingKey {
        case none, launchApp, quickLink, shellCommand, script, windowSnap, systemAction, screenshot
    }

    // Per-field tolerance: a missing/wrong-typed sibling string field (including
    // fields added by future versions) must not invalidate the whole payload.
    // (Swift's synthesized init throws on missing keys despite property defaults.)
    // Enum fields stay strict: invalid raw values throw so the payload degrades to .none.
    private static func field<T: Decodable, K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K, fallback: T) -> T {
        (try? c.decodeIfPresent(T.self, forKey: key)).flatMap { $0 } ?? fallback
    }

    private struct LaunchAppPayload: Codable {
        var bundlePath: String = ""
        var appName: String = ""
        enum K: String, CodingKey { case bundlePath, appName }
        init(bundlePath: String = "", appName: String = "") {
            self.bundlePath = bundlePath; self.appName = appName
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            bundlePath = CornerAction.field(c, .bundlePath, fallback: "")
            appName = CornerAction.field(c, .appName, fallback: "")
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encode(bundlePath, forKey: .bundlePath)
            try c.encode(appName, forKey: .appName)
        }
    }
    private struct QuickLinkPayload: Codable {
        var name: String = ""
        var url: String = ""
        var openWithBundleID: String? = nil
        enum K: String, CodingKey { case name, url, openWithBundleID }
        init(name: String = "", url: String = "", openWithBundleID: String? = nil) {
            self.name = name; self.url = url; self.openWithBundleID = openWithBundleID
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            name = CornerAction.field(c, .name, fallback: "")
            url = CornerAction.field(c, .url, fallback: "")
            openWithBundleID = (try? c.decodeIfPresent(String.self, forKey: .openWithBundleID)).flatMap { $0 }
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encode(name, forKey: .name)
            try c.encode(url, forKey: .url)
            try c.encodeIfPresent(openWithBundleID, forKey: .openWithBundleID)
        }
    }
    private struct ShellCommandPayload: Codable {
        var command: String = ""
        var shell: String = "/bin/zsh"
        enum K: String, CodingKey { case command, shell }
        init(command: String = "", shell: String = "/bin/zsh") {
            self.command = command; self.shell = shell
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            command = CornerAction.field(c, .command, fallback: "")
            shell = CornerAction.field(c, .shell, fallback: "/bin/zsh")
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encode(command, forKey: .command)
            try c.encode(shell, forKey: .shell)
        }
    }
    private struct ScriptPayload: Codable {
        var language: ScriptLanguage = .bash
        var path: String = ""
        var description: String = ""
        enum K: String, CodingKey { case language, path, description }
        init(language: ScriptLanguage = .bash, path: String = "", description: String = "") {
            self.language = language; self.path = path; self.description = description
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            // Strict: missing or invalid enum → throw → payload degrades to
            // .none rather than fabricating a default action.
            language = try c.decode(ScriptLanguage.self, forKey: .language)
            path = CornerAction.field(c, .path, fallback: "")
            description = CornerAction.field(c, .description, fallback: "")
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encode(language, forKey: .language)
            try c.encode(path, forKey: .path)
            try c.encode(description, forKey: .description)
        }
    }
    private struct WindowSnapPayload: Codable {
        var position: SnapPosition = .left
        enum K: String, CodingKey { case position }
        init(position: SnapPosition = .left) { self.position = position }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            position = try c.decode(SnapPosition.self, forKey: .position)
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encode(position, forKey: .position)
        }
    }
    private struct SystemActionPayload: Codable {
        var action: SystemAction = .spotlight
        enum K: String, CodingKey { case action }
        init(action: SystemAction = .spotlight) { self.action = action }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            action = try c.decode(SystemAction.self, forKey: .action)
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encode(action, forKey: .action)
        }
    }
    private struct ScreenshotPayload: Codable {
        var kind: ScreenshotKind = .full
        var destination: ScreenshotDestination = .clipboard
        var directory: String = "~/Pictures"
        enum K: String, CodingKey { case kind, destination, directory }
        init(kind: ScreenshotKind = .full, destination: ScreenshotDestination = .clipboard, directory: String = "~/Pictures") {
            self.kind = kind; self.destination = destination; self.directory = directory
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            kind = try c.decode(ScreenshotKind.self, forKey: .kind)
            destination = try c.decode(ScreenshotDestination.self, forKey: .destination)
            directory = CornerAction.field(c, .directory, fallback: "~/Pictures")
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encode(kind, forKey: .kind)
            try c.encode(destination, forKey: .destination)
            try c.encode(directory, forKey: .directory)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        // Deterministic winner for hand-crafted multi-key objects (document
        // order is not preserved by JSONDecoder; encoders never emit these).
        guard let key = container.allKeys.sorted(by: { $0.stringValue < $1.stringValue }).first else {
            self = .none
            return
        }
        switch key {
        case .none:
            self = .none
        case .launchApp:
            let p = (try? container.decode(LaunchAppPayload.self, forKey: .launchApp)) ?? LaunchAppPayload()
            self = p.bundlePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .none : .launchApp(bundlePath: p.bundlePath, appName: p.appName)
        case .quickLink:
            let p = (try? container.decode(QuickLinkPayload.self, forKey: .quickLink)) ?? QuickLinkPayload()
            self = p.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .none : .quickLink(name: p.name, url: p.url, openWithBundleID: p.openWithBundleID)
        case .shellCommand:
            let p = (try? container.decode(ShellCommandPayload.self, forKey: .shellCommand)) ?? ShellCommandPayload()
            self = p.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .none : .shellCommand(command: p.command, shell: p.shell)
        case .script:
            let p = (try? container.decode(ScriptPayload.self, forKey: .script)) ?? ScriptPayload()
            self = p.path.isEmpty ? .none : .script(language: p.language, path: p.path, description: p.description)
        case .windowSnap:
            // No default-fill here: a corrupt payload must degrade to .none,
            // never fabricate a snap the user didn't configure.
            guard let p = try? container.decode(WindowSnapPayload.self, forKey: .windowSnap) else {
                self = .none
                return
            }
            self = .windowSnap(position: p.position)
        case .systemAction:
            guard let p = try? container.decode(SystemActionPayload.self, forKey: .systemAction) else {
                self = .none
                return
            }
            self = .systemAction(p.action)
        case .screenshot:
            guard let p = try? container.decode(ScreenshotPayload.self, forKey: .screenshot) else {
                self = .none
                return
            }
            let directory = p.directory.isEmpty ? "~/Pictures" : p.directory
            self = .screenshot(kind: p.kind, destination: p.destination, directory: directory)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .none:
            try container.encode([String: String](), forKey: .none)
        case .launchApp(let bundlePath, let appName):
            try container.encode(LaunchAppPayload(bundlePath: bundlePath, appName: appName), forKey: .launchApp)
        case .quickLink(let name, let url, let openWithBundleID):
            try container.encode(QuickLinkPayload(name: name, url: url, openWithBundleID: openWithBundleID), forKey: .quickLink)
        case .shellCommand(let command, let shell):
            try container.encode(ShellCommandPayload(command: command, shell: shell), forKey: .shellCommand)
        case .script(let language, let path, let description):
            try container.encode(ScriptPayload(language: language, path: path, description: description), forKey: .script)
        case .windowSnap(let position):
            try container.encode(WindowSnapPayload(position: position), forKey: .windowSnap)
        case .systemAction(let action):
            try container.encode(SystemActionPayload(action: action), forKey: .systemAction)
        case .screenshot(let kind, let destination, let directory):
            try container.encode(ScreenshotPayload(kind: kind, destination: destination, directory: directory), forKey: .screenshot)
        }
    }
}

// Config for one screen's 4 corners
struct ScreenCornerConfig: Codable, Equatable {
    var corners: [String: CornerAction]

    enum K: String, CodingKey { case corners }

    init(corners: [String: CornerAction]) {
        self.corners = corners
    }

    init(from decoder: Decoder) throws {
        // Per-corner tolerance: one corrupt corner degrades to .none,
        // the rest survive.
        var corners: [String: CornerAction] = [:]
        if let container = try? decoder.container(keyedBy: K.self),
           let nested = try? container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .corners) {
            for key in nested.allKeys {
                corners[key.stringValue] = (try? nested.decode(CornerAction.self, forKey: key)) ?? CornerAction.none
            }
        }
        for corner in Corner.allCases where corners[corner.rawValue] == nil {
            corners[corner.rawValue] = .none
        }
        self.corners = corners
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: K.self)
        try container.encode(corners, forKey: .corners)
    }
    
    static var empty: ScreenCornerConfig {
        ScreenCornerConfig(corners: [
            Corner.topLeft.rawValue: .none,
            Corner.topRight.rawValue: .none,
            Corner.bottomLeft.rawValue: .none,
            Corner.bottomRight.rawValue: .none
        ])
    }
    
    func action(for corner: Corner) -> CornerAction {
        return corners[corner.rawValue] ?? CornerAction.none
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
    /// Liquid Glass on macOS 26+. Ignored on older systems (legacy look kept).
    var useLiquidGlass: Bool
    /// Schema version. v1 = pre-action builds, v2 = action categories.
    /// Old builds ignore unknown keys, so this is forward-safe.
    var configVersion: Int
    
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
        case screenConfigs, defaultConfig, dwellTime, hitZoneSize, isActive, monitorMode, autoCheckUpdates, useLiquidGlass, configVersion
    }
    
    init(screenConfigs: [String: ScreenCornerConfig], defaultConfig: ScreenCornerConfig, dwellTime: Double, hitZoneSize: Double, isActive: Bool, monitorMode: MonitorMode, autoCheckUpdates: Bool = true, useLiquidGlass: Bool = true, configVersion: Int = 2) {
        self.screenConfigs = screenConfigs
        self.defaultConfig = defaultConfig
        self.dwellTime = dwellTime
        self.hitZoneSize = hitZoneSize
        self.isActive = isActive
        self.monitorMode = monitorMode
        self.autoCheckUpdates = autoCheckUpdates
        self.useLiquidGlass = useLiquidGlass
        self.configVersion = configVersion
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Tolerant reader: any single corrupt/wrong-typed field falls back to
        // its default instead of wiping the whole config to .default.
        func value<T: Decodable>(_ key: CodingKeys, fallback d: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)).flatMap { $0 } ?? d
        }
        // Per-screen tolerance: one corrupt screen entry must not wipe the rest.
        var screens: [String: ScreenCornerConfig] = [:]
        if let nested = try? container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .screenConfigs) {
            for key in nested.allKeys {
                if let screen = try? nested.decode(ScreenCornerConfig.self, forKey: key) {
                    screens[key.stringValue] = screen
                }
            }
        }
        screenConfigs = screens
        defaultConfig = value(.defaultConfig, fallback: .empty)
        dwellTime = value(.dwellTime, fallback: 0.15)
        hitZoneSize = value(.hitZoneSize, fallback: 15.0)
        isActive = value(.isActive, fallback: true)
        monitorMode = value(.monitorMode, fallback: .allScreens)
        autoCheckUpdates = value(.autoCheckUpdates, fallback: true)
        useLiquidGlass = value(.useLiquidGlass, fallback: true)
        configVersion = value(.configVersion, fallback: 1)
    }
}
