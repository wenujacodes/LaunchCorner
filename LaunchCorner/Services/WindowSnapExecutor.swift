import AppKit
import ApplicationServices

// Moves the frontmost window to a half or quarter of the screen under the mouse.
enum WindowSnapExecutor {
    private struct SnapContext {
        let pid: pid_t
        let visibleFrame: NSRect
        let primaryHeight: CGFloat
    }

    @discardableResult
    static func snap(_ position: SnapPosition) -> Bool {
        // Everything (including AX SETS) runs on main: sets targeting our own
        // windows resolve in-process through AppKit, which traps off-main
        // (EXC_BREAKPOINT "Must only be used from the main thread"). Main is
        // serial, so this also serializes concurrent snaps.
        MainThread.value {
            snapLocked(position)
        }
    }

    private static func snapLocked(_ position: SnapPosition) -> Bool {
        guard let ctx = captureContext() else {
            return false
        }
        let appElement = AXUIElementCreateApplication(ctx.pid)

        var focusedRef: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef)
        guard focusErr == .success, let rawWindow = focusedRef else {
            print("Snap: no focused window (err \(focusErr.rawValue))")
            return false
        }
        guard CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else {
            print("Snap: focused window is not an AXUIElement")
            return false
        }
        let window = unsafeBitCast(rawWindow, to: AXUIElement.self)

        if isFlagSet(window, attribute: kAXMinimizedAttribute as CFString) {
            print("Snap: window is minimized, skipping")
            return false
        }
        // No SDK constant for this attribute name; use the documented AX string.
        if isFlagSet(window, attribute: "AXFullScreen" as CFString) {
            print("Snap: window is fullscreen, skipping")
            return false
        }

        let vf = ctx.visibleFrame

        let target: NSRect
        switch position {
        case .left:
            target = NSRect(x: vf.minX, y: vf.minY, width: vf.width / 2, height: vf.height)
        case .right:
            target = NSRect(x: vf.minX + vf.width / 2, y: vf.minY, width: vf.width / 2, height: vf.height)
        case .top:
            target = NSRect(x: vf.minX, y: vf.minY + vf.height / 2, width: vf.width, height: vf.height / 2)
        case .bottom:
            target = NSRect(x: vf.minX, y: vf.minY, width: vf.width, height: vf.height / 2)
        case .topLeft:
            target = NSRect(x: vf.minX, y: vf.minY + vf.height / 2, width: vf.width / 2, height: vf.height / 2)
        case .topRight:
            target = NSRect(x: vf.minX + vf.width / 2, y: vf.minY + vf.height / 2, width: vf.width / 2, height: vf.height / 2)
        case .bottomLeft:
            target = NSRect(x: vf.minX, y: vf.minY, width: vf.width / 2, height: vf.height / 2)
        case .bottomRight:
            target = NSRect(x: vf.minX + vf.width / 2, y: vf.minY, width: vf.width / 2, height: vf.height / 2)
        }

        let axY = ctx.primaryHeight - target.maxY
        var axPos = CGPoint(x: target.minX, y: axY)
        var axSize = CGSize(width: target.width, height: target.height)
        guard let posValue = AXValueCreate(.cgPoint, &axPos) else {
            print("Snap: failed to create position value")
            return false
        }
        guard let sizeValue = AXValueCreate(.cgSize, &axSize) else {
            print("Snap: failed to create size value")
            return false
        }

        func applyOnce() -> AXError {
            // Size first: growing the window can shift its top-left on some apps.
            let sizeErr = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            let posErr = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
            if sizeErr == .success, posErr == .success { return .success }
            return sizeErr != .success ? sizeErr : posErr
        }

        func isSettled() -> Bool {
            guard let pos = readPoint(window, attribute: kAXPositionAttribute as CFString),
                  let size = readSize(window, attribute: kAXSizeAttribute as CFString)
            else { return false }
            return abs(pos.x - axPos.x) <= 2 && abs(pos.y - axPos.y) <= 2
                && abs(size.width - axSize.width) <= 2 && abs(size.height - axSize.height) <= 2
        }

        for _ in 0..<3 {
            let err = applyOnce()
            // Rejecting apps (Electron without manual AX, Finder desktop, SIP windows):
            // don't spin, fail fast.
            if err == .cannotComplete || err == .notImplemented || err == .attributeUnsupported {
                print("Snap: window rejected set (\(err.rawValue))")
                return false
            }
            // Re-set position (size changes can drift it), then verify read-back.
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
            if isSettled() { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        print("Snap: failed to settle window position/size")
        return false
    }

    private static func readPoint(_ window: AXUIElement, attribute: CFString) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute, &ref) == .success,
              let value = ref, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func readSize(_ window: AXUIElement, attribute: CFString) -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute, &ref) == .success,
              let value = ref, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    private static func isFlagSet(_ window: AXUIElement, attribute: CFString) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute, &ref) == .success,
              let value = ref else {
            return false
        }
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return false
    }

    private static func captureContext() -> SnapContext? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            print("Snap: no frontmost application")
            return nil
        }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main ?? NSScreen.screens.first
        else {
            print("Snap: no screen found")
            return nil
        }
        return SnapContext(pid: frontApp.processIdentifier,
                           visibleFrame: screen.visibleFrame,
                           primaryHeight: NSScreen.screens.first?.frame.height ?? screen.frame.height)
    }
}
