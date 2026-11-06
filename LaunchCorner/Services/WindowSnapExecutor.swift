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
        // Fullscreen windows live in their own Space and can't be snapped
        // there: exit fullscreen, then snap once the window lands back.
        // No SDK constant for this attribute name; use the documented AX string.
        if isFlagSet(window, attribute: "AXFullScreen" as CFString) {
            let cleared = AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse) == .success
            print("Snap: exiting fullscreen (cleared: \(cleared)), retrying after settle")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                _ = snap(position)
            }
            return cleared
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

        // Electron/Chromium often reject resizes while enhanced UI is on;
        // disable it for the set and restore after (Loop's fix).
        let enhancedWasOn = setEnhancedUI(appElement, enabled: false)
        defer {
            if enhancedWasOn {
                setEnhancedUI(appElement, enabled: true)
            }
        }

        @discardableResult
        func apply() -> AXError {
            // Always size → position → size. Verified empirically: leading
            // with position leaves the height too tall (422/506 vs 416.5
            // target on this display), size-first lands exact. Trailing size
            // re-asserts the final size after the move.
            let sizeErr = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            let posErr = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
            let sizeErr2 = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            if sizeErr2 == .success, posErr == .success { return .success }
            return sizeErr != .success ? sizeErr : posErr
        }

        func isSettled() -> Bool {
            guard let pos = readPoint(window, attribute: kAXPositionAttribute as CFString),
                  let size = readSize(window, attribute: kAXSizeAttribute as CFString)
            else { return false }
            return abs(pos.x - axPos.x) <= 2 && abs(pos.y - axPos.y) <= 2
                && abs(size.width - axSize.width) <= 2 && abs(size.height - axSize.height) <= 2
        }

        // Verify with patience: the window server applies sets asynchronously
        // (a big shrink reads back mid-flight). Fast path first, no stall.
        var err = apply()
        // Rejecting apps (Finder desktop, SIP windows): don't spin, fail fast.
        if err == .cannotComplete || err == .notImplemented || err == .attributeUnsupported {
            print("Snap: window rejected set (\(err.rawValue))")
            return false
        }
        if isSettled() { return true }
        Thread.sleep(forTimeInterval: 0.25)
        if isSettled() { return true }
        err = apply()
        if err == .success {
            Thread.sleep(forTimeInterval: 0.25)
            if isSettled() { return true }
        }
        // Size-constrained windows (min/max sizes) land nearby but not exact:
        // re-anchor the final frame inside the target instead of failing.
        anchorInsideTarget(window: window, target: target, primaryHeight: ctx.primaryHeight)
        return isSettled()
    }

    /// Pushes a size-constrained window's origin so the final frame sits
    /// inside the target rect (Loop's anchored-frame correction).
    private static func anchorInsideTarget(window: AXUIElement, target: NSRect, primaryHeight: CGFloat) {
        guard let pos = readPoint(window, attribute: kAXPositionAttribute as CFString),
              let size = readSize(window, attribute: kAXSizeAttribute as CFString) else { return }
        var cocoa = NSRect(x: pos.x, y: primaryHeight - pos.y - size.height, width: size.width, height: size.height)
        cocoa.origin.x = min(max(cocoa.origin.x, target.minX), max(target.minX, target.maxX - cocoa.width))
        cocoa.origin.y = min(max(cocoa.origin.y, target.minY), max(target.minY, target.maxY - cocoa.height))
        var fixed = CGPoint(x: cocoa.minX, y: primaryHeight - cocoa.maxY)
        if let v = AXValueCreate(.cgPoint, &fixed) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
        }
    }

    @discardableResult
    private static func setEnhancedUI(_ appElement: AXUIElement, enabled: Bool) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, &ref) == .success,
              let current = (ref as? NSNumber)?.boolValue, current != enabled else {
            return false
        }
        let err = AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, enabled ? kCFBooleanTrue : kCFBooleanFalse)
        return err == .success
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
                           primaryHeight: NSScreen.main?.frame.height ?? NSScreen.screens.first?.frame.height ?? screen.frame.height)
    }
}
