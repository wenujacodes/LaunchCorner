import Foundation

// Runs a value-producing closure on the main thread without deadlocking
// when already on it. AppKit (NSWorkspace, NSScreen, NSEvent) requires main.
enum MainThread {
    static func value<T>(_ work: @escaping () -> T) -> T {
        if Thread.isMainThread {
            return work()
        }
        return DispatchQueue.main.sync(execute: work)
    }
}
