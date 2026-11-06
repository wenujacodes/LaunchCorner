import AppKit

// Test harness for scripts/test_actions.py. NOT part of the app target.
// Usage: lc_harness <mode> [args...]. Prints machine-readable lines.
func out(_ s: String) { print(s); fflush(stdout) }

@main
struct Harness {
    static func main() {
        harnessMain(CommandLine.arguments)
    }
}

func harnessMain(_ args: [String]) {
guard args.count >= 2 else { out("USAGE"); exit(2) }

switch args[1] {
case "model":
    var n = 0
    func t(_ id: String, _ ok: Bool, _ detail: String = "") {
        n += 1; out("MODEL \(id) \(ok ? "PASS" : "FAIL") \(detail)")
    }
    let dec = JSONDecoder(), enc = JSONEncoder()
    func decode(_ s: String) -> CornerAction? { try? dec.decode(CornerAction.self, from: Data(s.utf8)) }
    func isNone(_ s: String) -> Bool { guard let v = decode(s) else { return false }; return v == .none }
    // Old wire format (pre-action builds) must survive
    t("old-none", isNone("{\"none\":{}}"))
    t("old-launch", decode("{\"launchApp\":{\"bundlePath\":\"/Applications/Safari.app\",\"appName\":\"Safari\"}}") == .launchApp(bundlePath: "/Applications/Safari.app", appName: "Safari"))
    // Unknown future keys degrade, never drop the config
    t("unknown-key", isNone("{\"teleport\":{\"x\":1}}"))
    t("empty-obj", isNone("{}"))
    // New cases round-trip
    let cases: [CornerAction] = [
        .quickLink(name: "N", url: "https://example.com", openWithBundleID: nil),
        .quickLink(name: "", url: "shortcuts://run-shortcut?name=X", openWithBundleID: "com.apple.Safari"),
        .script(language: .appleScript, path: "/tmp/x.scpt", description: ""),
        .script(language: .python, path: "/tmp/x.py", description: "d"),
        .windowSnap(position: .bottomRight),
        .systemAction(.appExpose),
        .screenshot(kind: .window, destination: .file, directory: "~/Pictures"),
    ]
    for (i, c) in cases.enumerated() {
        if let d = try? enc.encode(c), let back = try? dec.decode(CornerAction.self, from: d) {
            t("roundtrip-\(i)", back == c, c.displayName)
        } else { t("roundtrip-\(i)", false, c.displayName) }
    }
    // Corrupt nested enums must degrade to .none, never fabricate an action
    t("bad-snap", isNone("{\"windowSnap\":{\"position\":\"diagonal\"}}"))
    t("bad-sys", isNone("{\"systemAction\":{\"action\":\"bogus\"}}"))
    t("bad-shot", isNone("{\"screenshot\":{\"kind\":\"bogus\"}}"))
    t("bad-lang", isNone("{\"script\":{\"language\":\"bogus\",\"path\":\"/x\"}}"))
    // Corrupt AppConfig fields fall back per-field; valid corners survive
    let corruptCfg = "{\"screenConfigs\":{},\"defaultConfig\":{\"corners\":{\"topLeft\":{\"launchApp\":{\"bundlePath\":\"/Applications/Safari.app\",\"appName\":\"Safari\"}}}},\"dwellTime\":\"fast\",\"monitorMode\":\"bogus\",\"isActive\":true}"
    if let back = try? dec.decode(AppConfig.self, from: Data(corruptCfg.utf8)) {
        t("cfg-tolerant", back.defaultConfig.action(for: .topLeft) == .launchApp(bundlePath: "/Applications/Safari.app", appName: "Safari")
            && back.dwellTime == 0.15 && back.monitorMode == .allScreens)
    } else { t("cfg-tolerant", false) }
    // Empty payloads normalize to .none (never fire)
    t("empty-url", isNone("{\"quickLink\":{\"name\":\"\",\"url\":\"  \"}}"))
    t("empty-script", isNone("{\"script\":{\"language\":\"python\",\"path\":\"\"}}"))
    // Removed payloads degrade to .none (toggleAppearance/missionControl/
    // showDesktop/shellCommand no longer exist)
    t("gone-shell", isNone("{\"shellCommand\":{\"command\":\"echo hi\",\"shell\":\"/bin/zsh\"}}"))
    t("gone-mission", isNone("{\"systemAction\":{\"action\":\"missionControl\"}}"))
    // Full AppConfig with mixed corners survives
    var cfg = AppConfig.default
    cfg.defaultConfig.setAction(.launchApp(bundlePath: "/Applications/Safari.app", appName: "Safari"), for: .topLeft)
    cfg.defaultConfig.setAction(.windowSnap(position: .left), for: .topRight)
    cfg.defaultConfig.setAction(.systemAction(.spotlight), for: .bottomLeft)
    if let d = try? enc.encode(cfg), let back = try? dec.decode(AppConfig.self, from: d) {
        t("appconfig", back == cfg)
    } else { t("appconfig", false) }
    // Every case has UI strings (exhaustiveness doubles as dispatch coverage proof)
    let all: [CornerAction] = [.none,
        .launchApp(bundlePath: "/a", appName: "b"),
        .quickLink(name: "", url: "https://e.com", openWithBundleID: nil),
        .script(language: .bash, path: "/s.sh", description: ""),
        .script(language: .go, path: "/p", description: ""),
        .windowSnap(position: .top),
        .systemAction(.lockScreen),
        .screenshot(kind: .full, destination: .clipboard, directory: "~/Pictures")]
    t("strings", all.allSatisfy { !$0.displayName.isEmpty && !$0.symbolName.isEmpty })
    t("configured", CornerAction.none.isConfigured == false
        && CornerAction.windowSnap(position: .left).isConfigured
        && CornerAction.quickLink(name: "", url: "", openWithBundleID: nil).isConfigured == false)
    out("MODEL-DONE \(n)")

case "interp":
    guard args.count >= 3, let lang = ScriptLanguage(rawValue: args[2]) else {
        out("INTERP BAD-LANG"); exit(2)
    }
    out("INTERP \(ShellExecutor.resolveInterpreter(lang) ?? "MISSING")")

case "runscript":
    guard args.count >= 4, let lang = ScriptLanguage(rawValue: args[2]) else {
        out("RUNSCRIPT BAD-ARGS"); exit(2)
    }
    ShellExecutor.runScript(language: lang, path: args[3])
    Thread.sleep(forTimeInterval: 5.0)
    out("RUNSCRIPT-DONE")

case "ql":
    let u = QuickLinkExecutor.targetURL(for: args[2])
    out("QL scheme=\(u.scheme ?? "nil") isFile=\(u.isFileURL) url=\(u.absoluteString)")

case "ax":
    out("AX \(AXIsProcessTrusted() ? "YES" : "NO")")

case "shot":
    guard args.count >= 5,
          let kind = ScreenshotKind(rawValue: args[2]),
          let dest = ScreenshotDestination(rawValue: args[3]) else {
        out("SHOT BAD-ARGS"); exit(2)
    }
    SystemActionExecutor.screenshot(kind: kind, destination: dest, directory: args[4])
    Thread.sleep(forTimeInterval: 8.0) // let async run print through
    out("SHOT-DONE")

case "shotclip":
    NSPasteboard.general.clearContents()
    let before = NSPasteboard.general.changeCount
    SystemActionExecutor.screenshot(kind: .full, destination: .clipboard, directory: "~/Pictures")
    Thread.sleep(forTimeInterval: 4.0)
    let types = NSPasteboard.general.types ?? []
    let hasImage = NSPasteboard.general.changeCount != before && (types.contains(.tiff) || types.contains(.png))
    out("CLIPIMAGE \(hasImage ? "YES" : "NO")")

case "spotkey":
    guard AXIsProcessTrusted() else { out("SPOT-NO-AX"); break }
    KeyPress.key(49, .maskCommand) // Cmd+Space
    Thread.sleep(forTimeInterval: 0.8)
    KeyPress.key(53, []) // Esc dismisses
    out("SPOT-OK")

case "snaptest":
    snaptestMain()

case "snaptest-bg":
    // Same coverage with an off-main CALLER: pre-fix this crashed inside
    // AXUIElementSetAttributeValue (AppKit resolved our own window off-main).
    // Main pumps a runloop while waiting (bg work hops back to main).
    let sem = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .userInitiated).async {
        snaptestMain()
        sem.signal()
    }
    while sem.wait(timeout: .now() + 0.2) == .timedOut {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    }
    out("SNAPBG-DONE")

case "fuzz":
    fuzzMain()

default:
    out("UNKNOWN-MODE"); exit(2)
}

// MARK: - Codable fuzz battery: hostile inputs must never crash,
// and must decode to .none or a sane action (never throw out of AppConfig).
func fuzzMain() {
    let dec = JSONDecoder()
    let actions = [
        "{\"windowSnap\":null}", "{\"windowSnap\":5}", "{\"windowSnap\":[]}",
        "{\"windowSnap\":{\"position\":null}}", "{\"windowSnap\":{\"position\":5}}",
        "{\"windowSnap\":{\"position\":\"LEFT\"}}", "{\"windowSnap\":{\"position\":\" left\"}}",
        "{\"systemAction\":{\"action\":0}}", "{\"systemAction\":{\"action\":true}}",
        "{\"systemAction\":{}}", "{\"screenshot\":{}}", "{\"script\":{}}",
        "{\"launchApp\":null}", "{\"launchApp\":{\"bundlePath\":null}}",
        "{\"launchApp\":{\"bundlePath\":123,\"appName\":[]}}",
        "{\"quickLink\":{\"url\":{}}}", "{\"quickLink\":[]}",
        "{\"a\":1,\"b\":2}", "{\"none\":null,\"launchApp\":null}",
        "[1,2]", "\"str\"", "123", "null", "true", "{}",
        "{\"windowSnap\":{\"position\":\"left\",\"extra\":{}}}",
        "{\"screenshot\":{\"kind\":\"full\",\"destination\":\"file\"}}",
        String(repeating: "{\"a\":", count: 500),
        "{\"url\":\"https://e.com/\\ud800\"}",
        "{\"command\":\"" + String(repeating: "x", count: 100000) + "\"}",
    ]
    var crashed = 0, nonNone = 0
    for s in actions {
        let v = try? dec.decode(CornerAction.self, from: Data(s.utf8))
        if v.map({ $0 != CornerAction.none }) ?? false { nonNone += 1 }
        _ = try? dec.decode(AppConfig.self, from: Data(s.utf8))
    }
    // AppConfig-level hostility: one poisoned screen/corner must not wipe others.
    let cfgBlobs = [
        "{\"screenConfigs\":{\"bad\":{\"corners\":[]},\"good\":{\"corners\":{\"topLeft\":{\"windowSnap\":{\"position\":\"left\"}}}}}",
        "{\"defaultConfig\":{\"corners\":{\"topLeft\":[1],\"topRight\":{\"systemAction\":{\"action\":\"spotlight\"}}}}",
        "{\"defaultConfig\":null,\"dwellTime\":{},\"isActive\":\"yes\"}",
    ]
    var cfgOk = 0
    for s in cfgBlobs {
        if (try? dec.decode(AppConfig.self, from: Data(s.utf8))) != nil { cfgOk += 1 }
    }
    out("FUZZ actions=\(actions.count) nonNone=\(nonNone) configs=\(cfgOk)/\(cfgBlobs.count)")
}

// MARK: - snap end-to-end (launches TextEdit, snaps, verifies, cleans up)
func snaptestMain() {
    guard AXIsProcessTrusted() else { out("SNAP SKIP-NO-AX"); return }
    let fm = FileManager.default
    let testFile = "/tmp/lc_snap_test.txt"
    try? "snap me".write(toFile: testFile, atomically: true, encoding: .utf8)
    let wasRunning = MainThread.value {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first != nil
    }
    MainThread.value { NSWorkspace.shared.open(URL(fileURLWithPath: testFile)) }
    // wait for frontmost TextEdit (≤10s)
    var ok = false
    for _ in 0..<100 {
        Thread.sleep(forTimeInterval: 0.1)
        let front = MainThread.value { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
        if front == "com.apple.TextEdit" { ok = true; break }
    }
    guard ok else { out("SNAP FAIL-frontmost"); return }
    Thread.sleep(forTimeInterval: 0.5)
    func check(_ pos: SnapPosition) -> Bool {
        guard WindowSnapExecutor.snap(pos) else { return false }
        Thread.sleep(forTimeInterval: 0.3)
        // read back focused window geometry
        guard let app = MainThread.value({ NSWorkspace.shared.frontmostApplication }) else { return false }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let raw = ref, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return false }
        let win = unsafeBitCast(raw, to: AXUIElement.self)
        var pRef: CFTypeRef?, sRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &pRef) == .success,
              AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sRef) == .success,
              let pv = pRef, let sv = sRef else { return false }
        var pt = CGPoint.zero, sz = CGSize.zero
        guard let pv = pRef, let sv = sRef,
              CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID() else { return false }
        let pvv = unsafeBitCast(pv, to: AXValue.self), svv = unsafeBitCast(sv, to: AXValue.self)
        guard AXValueGetType(pvv) == .cgPoint, AXValueGetType(svv) == .cgSize,
              AXValueGetValue(pvv, .cgPoint, &pt), AXValueGetValue(svv, .cgSize, &sz) else { return false }
        // expected rect in AX coords
        let mouse = MainThread.value { NSEvent.mouseLocation }
        guard let screen = MainThread.value({
            NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        }) else {
            out("SNAP SKIP-NO-SCREEN"); return false
        }
        let vf = screen.visibleFrame
        let ph = NSScreen.main?.frame.height ?? NSScreen.screens.first?.frame.height ?? vf.height
        func ax(_ r: NSRect) -> NSRect { NSRect(x: r.minX, y: ph - r.maxY, width: r.width, height: r.height) }
        let exp: NSRect
        switch pos {
        case .left: exp = ax(NSRect(x: vf.minX, y: vf.minY, width: vf.width/2, height: vf.height))
        case .bottomRight: exp = ax(NSRect(x: vf.minX+vf.width/2, y: vf.minY, width: vf.width/2, height: vf.height/2))
        default: exp = .zero
        }
        return abs(pt.x-exp.minX)<=8 && abs(pt.y-exp.minY)<=8 && abs(sz.width-exp.width)<=8 && abs(sz.height-exp.height)<=8
    }
    let l = check(.left), q = check(.bottomRight)
    out("SNAP left=\(l ? "PASS" : "FAIL") quarter=\(q ? "PASS" : "FAIL")")
    // cleanup: close our window via AX, quit TextEdit only if we launched it
    if let app = MainThread.value({
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first
    }) {
        let el = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXFocusedWindowAttribute as CFString, &ref) == .success, let raw = ref {
            let win = unsafeBitCast(raw, to: AXUIElement.self)
            var wins: CFTypeRef?
            if AXUIElementCopyAttributeValue(win, kAXChildrenAttribute as CFString, &wins) == .success, let kids = wins as? [AXUIElement] {
                for k in kids {
                    var sub: CFTypeRef?
                    if AXUIElementCopyAttributeValue(k, kAXSubroleAttribute as CFString, &sub) == .success,
                       (sub as? String) == kAXCloseButtonSubrole as String {
                        AXUIElementPerformAction(k, kAXPressAction as CFString)
                        break
                    }
                }
            }
        }
        Thread.sleep(forTimeInterval: 0.5)
        if !wasRunning { MainThread.value { app.terminate() } }
    }
    try? fm.removeItem(atPath: testFile)
}
} // end harnessMain
