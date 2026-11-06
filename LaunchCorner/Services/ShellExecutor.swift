import Foundation
import AppKit

// Runs shell commands and script files without blocking the caller.
enum ShellExecutor {
    static func availableShells() -> [String] {
        var shells: [String] = []
        if let contents = try? String(contentsOfFile: "/etc/shells", encoding: .utf8) {
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                if !shells.contains(trimmed) {
                    shells.append(trimmed)
                }
            }
        }
        for extra in ["/bin/sh", "/bin/bash", "/bin/zsh", "/usr/local/bin/fish", "/opt/homebrew/bin/fish"] {
            if !shells.contains(extra) {
                shells.append(extra)
            }
        }
        let existing = shells.filter { FileManager.default.isExecutableFile(atPath: $0) }
        return existing.isEmpty ? ["/bin/zsh", "/bin/bash", "/bin/sh"] : existing
    }

    static func runShellCommand(_ command: String, shell: String, visible: Bool = true) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("Shell: empty command")
            return
        }
        let shellPath = shell.isEmpty ? "/bin/zsh" : shell
        guard FileManager.default.isExecutableFile(atPath: shellPath) else {
            print("Shell: interpreter not executable: \(shellPath)")
            return
        }
        if !visible {
            // Headless (tests): classic background run.
            DispatchQueue.global(qos: .utility).async {
                WatchedProcess.run(path: shellPath, args: ["-c", trimmed],
                                   cwd: FileManager.default.homeDirectoryForCurrentUser,
                                   label: "Shell")
            }
            return
        }
        // Visible: hand a .command file to the user's default terminal app
        // (default .command handler), so the command runs in a real window.
        DispatchQueue.global(qos: .utility).async {
            let stamp = UInt64(Date().timeIntervalSince1970 * 1000) % 100000
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("LaunchCorner-\(stamp).command")
            // Keep-open tail: `read` exists in sh/bash/zsh/fish; other shells
            // show its error after the command output, window still stays open.
            let body = "#!\(shellPath)\n\(trimmed)\necho \"\"\necho \"[LaunchCorner] done — press Enter to close\"\nread lc_done\n"
            do {
                try body.write(to: fileURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                      ofItemAtPath: fileURL.path)
            } catch {
                print("Shell: failed to stage .command file: \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.async {
                // Default handler (what the user picked for command files),
                // so this honors their default terminal app.
                if !NSWorkspace.shared.open(fileURL) {
                    print("Shell: system declined to open terminal for command")
                }
            }
        }
    }

    static func resolveInterpreter(_ language: ScriptLanguage) -> String? {
        for candidate in language.interpreterCandidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    static func runScript(language: ScriptLanguage, path: String) {
        guard !path.isEmpty else {
            print("Script: empty path")
            return
        }
        guard let interpreter = resolveInterpreter(language) else {
            if language == .csharp {
                print("Script: no C# interpreter found. Install dotnet-script: brew install dotnet + dotnet tool install -g dotnet-script")
            } else {
                print("Script: no interpreter found for \(language.rawValue)")
            }
            return
        }
        let expandedPath = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            print("Script: file not found: \(expandedPath)")
            return
        }
        let arguments: [String]
        if language == .go || URL(fileURLWithPath: interpreter).lastPathComponent.contains("deno") {
            // go run / deno run take the file as a subcommand argument.
            arguments = ["run", expandedPath]
        } else {
            // bash, osascript, python, node, ts-node/tsx, ruby, dotnet-script.
            arguments = [expandedPath]
        }
        DispatchQueue.global(qos: .utility).async {
            WatchedProcess.run(path: interpreter, args: arguments,
                               cwd: FileManager.default.homeDirectoryForCurrentUser,
                               label: "Script")
        }
    }
}
