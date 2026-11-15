import AppKit
import Foundation

// Opens URLs, file paths, and shortcuts:// links, optionally with a specific app.
enum QuickLinkExecutor {
    static func open(urlString: String, openWithBundleID: String?) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("QuickLink: empty URL")
            return
        }

        let targetURL = targetURL(for: trimmed)

        if targetURL.scheme == "shortcuts" {
            openShortcutFallback(targetURL)
            return
        }
        openDefault(targetURL: targetURL, openWithBundleID: openWithBundleID)
    }

    /// Pure string→URL resolution (testable): URLs (with space fallback),
    /// otherwise tilde-expanded file paths.
    static func targetURL(for raw: String) -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded), url.scheme != nil {
            // Catches raw strings with spaces, e.g. shortcuts://run-shortcut?name=My Shortcut
            return url
        }
        let expanded = (trimmed as NSString).expandingTildeInPath
        if (expanded as NSString).isAbsolutePath {
            return URL(fileURLWithPath: expanded)
        }
        // Relative paths resolve against home (NSWorkspace can't open relative file URLs).
        return URL(fileURLWithPath: expanded, relativeTo: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// NSWorkspace.open must run on the main thread; shortcuts:// also gets a
    /// CLI fallback (`/usr/bin/shortcuts run`) since a misspelled name fails silently.
    private static func openShortcutFallback(_ url: URL) {
        DispatchQueue.main.async {
            if NSWorkspace.shared.open(url) { return }
            guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  comps.host?.contains("run-shortcut") == true || comps.path.contains("run-shortcut"),
                  let name = comps.queryItems?.first(where: { $0.name == "name" })?.value,
                  !name.isEmpty
            else {
                print("QuickLink: failed to open \(url.scheme ?? "?") link")
                return
            }
            // Fork off-main; WatchedProcess never blocks and enforces a timeout.
            DispatchQueue.global(qos: .utility).async {
                WatchedProcess.run(path: "/usr/bin/shortcuts", args: ["run", name], label: "QuickLink")
            }
        }
    }

    private static func openDefault(targetURL: URL, openWithBundleID: String?) {
        DispatchQueue.main.async {
            if let bundleID = openWithBundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !bundleID.isEmpty
            {
                guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                    print("QuickLink: app not found for bundle ID \(bundleID), opening with default handler")
                    NSWorkspace.shared.open(targetURL)
                    return
                }
                let configuration = NSWorkspace.OpenConfiguration()
                let linkHost = targetURL.host ?? targetURL.lastPathComponent
                NSWorkspace.shared.open([targetURL], withApplicationAt: appURL, configuration: configuration) { _, error in
                    if let error = error {
                        print("QuickLink: failed to open \(linkHost) with \(bundleID): \(error.localizedDescription)")
                    }
                }
                return
            }

            if !NSWorkspace.shared.open(targetURL) {
                print("QuickLink: system declined to open \(targetURL.scheme ?? "file") link")
            }
        }
    }
}
