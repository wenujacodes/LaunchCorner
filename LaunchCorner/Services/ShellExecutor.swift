import Foundation

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

    static func runShellCommand(_ command: String, shell: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("Shell: empty command")
            return
        }
        let shellPath = shell.isEmpty ? "/bin/zsh" : shell
        // Launched async: WatchedProcess never blocks, drains pipes, kills hangs.
        DispatchQueue.global(qos: .utility).async {
            WatchedProcess.run(path: shellPath, args: ["-c", trimmed],
                               cwd: FileManager.default.homeDirectoryForCurrentUser,
                               label: "Shell")
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
