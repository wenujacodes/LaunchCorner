import AppKit
import Foundation

// One Apple Shortcut installed on this Mac.
struct UserShortcut: Identifiable, Hashable {
    let name: String
    /// Stable UUID from `shortcuts list --show-identifiers`. Nil when the
    /// list output has no trailing identifier (older output, hand-typed).
    let identifier: String?

    // Stable across renames when the identifier is known.
    var id: String { identifier ?? name }
}

// Lists and runs Apple Shortcuts on this Mac.
//
// Apple surfaces (Shortcuts User Guide, macOS):
// - List: `shortcuts list --show-identifiers` ("Listing shortcuts on the
//   command line", support.apple.com/guide/shortcuts-mac)
// - Run headless: `shortcuts run "<name-or-id>"`
//   ("Run shortcuts from the command line")
// - Run from another app: `shortcuts://run-shortcut?name=...`
//   ("Run a shortcut using a URL scheme on Mac")
//
// Listing via the CLI needs no Automation permission prompt (unlike the
// `Shortcuts Events` AppleScript dictionary) and reading
// `~/Library/Shortcuts/` directly is TCC-gated, so the CLI is the
// supported discovery path.
enum ShortcutExecutor {
    static let cliPath = "/usr/bin/shortcuts"
    static let appBundleID = "com.apple.shortcuts"

    enum FetchError: LocalizedError {
        case cliMissing
        case timedOut
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .cliMissing: return "Shortcuts CLI not found (macOS 12+ required)."
            case .timedOut: return "Listing shortcuts timed out."
            case .failed(let s): return s.isEmpty ? "Could not list shortcuts." : s
            }
        }
    }

    /// Sorted shortcuts on this Mac. Never throws stale data: an empty
    /// library is a valid empty result, CLI problems throw.
    static func fetchShortcuts() async -> Result<[UserShortcut], Error> {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: fetchShortcutsSync(timeout: 10))
            }
        }
    }

    static func run(name: String, identifier: String?) {
        let target = targetString(name: name, identifier: identifier)
        guard !target.isEmpty else {
            print("Shortcut: empty name")
            return
        }
        // Stable identifiers survive renames; the CLI accepts either.
        if FileManager.default.isExecutableFile(atPath: cliPath) {
            DispatchQueue.global(qos: .utility).async {
                WatchedProcess.run(path: cliPath, args: ["run", target], label: "Shortcut")
            }
            return
        }
        // Pre-macOS 12 fallback: URL scheme (needs the Shortcuts app).
        var comps = URLComponents()
        comps.scheme = "shortcuts"
        comps.host = "run-shortcut"
        comps.queryItems = [URLQueryItem(name: "name", value: target)]
        guard let url = comps.url else {
            print("Shortcut: could not build run URL")
            return
        }
        DispatchQueue.main.async {
            if !NSWorkspace.shared.open(url) {
                print("Shortcut: system declined to run \(target)")
            }
        }
    }

    /// Opens the shortcut in the Shortcuts editor for troubleshooting
    /// (mirrors `shortcuts view "<name>"` from the Apple docs).
    static func view(name: String, identifier: String?) {
        let target = targetString(name: name, identifier: identifier)
        guard !target.isEmpty else { return }
        if FileManager.default.isExecutableFile(atPath: cliPath) {
            DispatchQueue.global(qos: .utility).async {
                WatchedProcess.run(path: cliPath, args: ["view", target], label: "ShortcutView")
            }
        }
    }

    static func openShortcutsApp() {
        DispatchQueue.main.async {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID) {
                NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
            }
        }
    }

    // MARK: - Internal (testable)

    static func targetString(name: String, identifier: String?) -> String {
        let id = (identifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty { return id }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses `shortcuts list --show-identifiers` output: one shortcut per
    /// line as `Name (UUID)`. Names may themselves contain parentheses, so
    /// only a trailing `(36-char UUID)` is treated as an identifier.
    static func parseListOutput(_ output: String) -> [UserShortcut] {
        var out: [UserShortcut] = []
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if let (name, id) = splitIdentifier(line) {
                out.append(UserShortcut(name: name, identifier: id))
            } else {
                out.append(UserShortcut(name: line, identifier: nil))
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func splitIdentifier(_ line: String) -> (String, String?)? {
        // Trailing " (XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX)".
        guard line.hasSuffix(")"),
              let range = line.range(of: " (", options: .backwards),
              range.upperBound < line.index(before: line.endIndex)
        else { return nil }
        let open = range.lowerBound
        let candidate = String(line[line.index(open, offsetBy: 2)..<line.index(before: line.endIndex)])
        guard candidate.count == 36, UUID(uuidString: candidate) != nil else { return nil }
        let name = String(line[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return (name, candidate.uppercased())
    }

    // MARK: - Sync CLI

    private static func fetchShortcutsSync(timeout: TimeInterval) -> Result<[UserShortcut], Error> {
        guard FileManager.default.isExecutableFile(atPath: cliPath) else {
            return .failure(FetchError.cliMissing)
        }
        // Single choke point for child processes (see WatchedProcess).
        guard let cap = WatchedProcess.capture(path: cliPath, args: ["list", "--show-identifiers"],
                                               label: "ShortcutList", timeout: timeout) else {
            return .failure(FetchError.failed("Could not launch the shortcuts CLI."))
        }
        if cap.timedOut {
            return .failure(FetchError.timedOut)
        }
        if cap.status != 0 {
            return .failure(FetchError.failed(cap.stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return .success(parseListOutput(cap.stdout))
    }
}
