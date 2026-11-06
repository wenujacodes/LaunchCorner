import AppKit
import CoreGraphics

// In-process key synthesis. No osascript child process (child would need its own TCC).
// Requires Accessibility permission (host app already holds it).
enum KeyPress {
    /// Synthesize a key down+up with the given modifier flags.
    static func key(_ virtualKey: UInt32, _ flags: CGEventFlags) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(virtualKey), keyDown: true) else {
            print("KeyPress: failed to create key-down event for \(virtualKey)")
            return
        }
        down.flags = flags
        down.post(tap: .cghidEventTap)

        guard let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(virtualKey), keyDown: false) else {
            print("KeyPress: failed to create key-up event for \(virtualKey)")
            return
        }
        up.flags = flags
        up.post(tap: .cghidEventTap)
    }

    /// Synthesize a media (NX) key. nxKeyType: 16 = play/pause, 17 = next, 18 = previous.
    static func mediaKey(_ nxKeyType: UInt32) {
        for isDown in [true, false] {
            // NSEvent construction is main-thread-only; posting is thread-safe.
            guard let event = MainThread.value({ makeMediaEvent(nxKeyType, isDown: isDown) }) else {
                print("KeyPress: failed to create media key event for \(nxKeyType)")
                return
            }
            guard let cgEvent = event.cgEvent else {
                print("KeyPress: failed to get CGEvent for media key \(nxKeyType)")
                return
            }
            cgEvent.post(tap: .cghidEventTap)
        }
    }

    private static func makeMediaEvent(_ nxKeyType: UInt32, isDown: Bool) -> NSEvent? {
        let data1 = Int((nxKeyType << 16) | (isDown ? 0xA00 : 0xB00))
        return NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )
    }
}
