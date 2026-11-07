import Foundation

// Runs script files without blocking the caller.
enum ShellExecutor {
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
