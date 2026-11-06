import Foundation
import AppKit

// Simple utility to execute corner actions. Everything runs off the main thread.
class ActionExecutor {
    static func execute(_ action: CornerAction) {
        DispatchQueue.global(qos: .userInitiated).async {
            switch action {
            case .none:
                break
            case .launchApp(let bundlePath, _):
                launchApp(atPath: bundlePath)
            case .quickLink(_, let url, let openWithBundleID):
                QuickLinkExecutor.open(urlString: url, openWithBundleID: openWithBundleID)
            case .shellCommand(let command, let shell):
                ShellExecutor.runShellCommand(command, shell: shell)
            case .script(let language, let path, _):
                ShellExecutor.runScript(language: language, path: path)
            case .windowSnap(let position):
                if !WindowSnapExecutor.snap(position) {
                    print("Failed to snap window to \(position.rawValue)")
                }
            case .systemAction(let systemAction):
                SystemActionExecutor.perform(systemAction)
            case .screenshot(let kind, let destination, let directory):
                SystemActionExecutor.screenshot(kind: kind, destination: destination, directory: directory)
            }
        }
    }
    
    static func launchApp(atPath path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        let configuration = NSWorkspace.OpenConfiguration()

        DispatchQueue.main.async {
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { (app, error) in
                if let error = error {
                    print("Failed to launch app at \(path): \(error.localizedDescription)")
                }
            }
        }
    }
}
