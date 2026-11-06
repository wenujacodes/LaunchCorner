import AppKit
import Foundation

// System actions and screenshots. All Process runs are async with a timeout.
enum SystemActionExecutor {
    static func perform(_ action: SystemAction) {
        switch action {
        case .spotlight:
            KeyPress.key(49, .maskCommand)
        case .mediaPlayPause:
            KeyPress.mediaKey(16)
        case .mediaNext:
            KeyPress.mediaKey(17)
        case .mediaPrevious:
            KeyPress.mediaKey(18)
        case .startScreenSaver:
            DispatchQueue.main.async {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"))
            }
        case .lockScreen:
            KeyPress.key(12, [.maskControl, .maskCommand])
        case .sleepDisplay:
            systemQueue.async {
                WatchedProcess.run(path: "/usr/bin/pmset", args: ["displaysleepnow"],
                                   cwd: FileManager.default.homeDirectoryForCurrentUser,
                                   label: "sleepDisplay")
            }
        case .appExpose:
            KeyPress.key(125, .maskControl)
        }
    }

    private static let systemQueue = DispatchQueue(label: "com.launchcorner.system")
    // Monotonic per-process counter: same-millisecond bursts can't collide.
    // (All mutations happen on systemQueue.)
    private static var shotCounter: UInt = 0

    static func screenshot(kind: ScreenshotKind, destination: ScreenshotDestination, directory: String) {
        // Screen Recording TCC gates the CALLING app: preflight first so the
        // system prompts instead of failing silently. Without a grant the
        // capture comes out blank — skip loudly and tell the user where to enable it.
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            print("Screenshot: needs Screen Recording access (System Settings > Privacy & Security > Screen Recording). Capture skipped.")
            return
        }
        var args: [String] = []
        switch kind {
        case .full:
            break
        case .selection:
            args.append("-i")
        case .window:
            // Front window directly; -iw would wait for a manual click instead.
            args.append("-w")
        }
        switch destination {
        case .clipboard:
            args.append("-c")
        case .file:
            let expanded = (directory as NSString).expandingTildeInPath
            let dirURL = URL(fileURLWithPath: expanded, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            } catch {
                print("Screenshot: failed to create directory \(expanded): \(error.localizedDescription)")
                return
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let stamp = formatter.string(from: Date())
            // Millisecond + pid + counter suffix: bursts can't collide.
            let unique = "\(stamp)-\(UInt64(Date().timeIntervalSince1970 * 1000) % 100000)-\(ProcessInfo.processInfo.processIdentifier)"
            let fileURL = dirURL.appendingPathComponent("Screenshot-\(unique).png")
            args.append(fileURL.path)
        }
        let finalArgs = args
        systemQueue.async {
            shotCounter += 1
            var namespaced = finalArgs
            if let last = namespaced.last, last.hasSuffix(".png") {
                let base = (last as NSString).deletingPathExtension
                namespaced[namespaced.count - 1] = "\(base)-\(shotCounter).png"
            }
            WatchedProcess.run(path: "/usr/sbin/screencapture", args: namespaced,
                               cwd: FileManager.default.homeDirectoryForCurrentUser,
                               label: "screencapture")
        }
    }
}

