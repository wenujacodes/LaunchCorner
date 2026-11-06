import Foundation

// Launches a child process without blocking the caller and without the two
// classic hangs: an undrained 64KB stdout/stderr pipe stalling the child,
// and a runaway child with no timeout. Stderr is drained concurrently and
// only a capped tail is kept for failure logs. Safe to call from any queue.
enum WatchedProcess {
    @discardableResult
    static func run(path: String, args: [String], cwd: URL? = nil,
                    label: String, timeout: TimeInterval = 30) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            print("\(label): not executable: \(path)")
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if let cwd {
            process.currentDirectoryURL = cwd
        }
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice

        let lock = NSLock()
        var errTail = Data()
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            lock.lock()
            errTail.append(chunk)
            if errTail.count > 8192 {
                errTail.removeFirst(errTail.count - 8192)
            }
            lock.unlock()
        }
        process.terminationHandler = { [label] proc in
            errPipe.fileHandleForReading.readabilityHandler = nil
            guard proc.terminationStatus != 0 else { return }
            lock.lock()
            let tail = String(data: errTail, encoding: .utf8) ?? ""
            lock.unlock()
            print("\(label): exited \(proc.terminationStatus): \(String(tail.suffix(2000)))")
        }
        do {
            try process.run()
        } catch {
            errPipe.fileHandleForReading.readabilityHandler = nil
            print("\(label): failed to launch \(path): \(error.localizedDescription)")
            return false
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [label] in
            if process.isRunning {
                process.terminate()
                print("\(label): timed out after \(Int(timeout))s, terminated")
            }
        }
        return true
    }
}
