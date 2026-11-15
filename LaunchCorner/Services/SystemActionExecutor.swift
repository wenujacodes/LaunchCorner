import AppKit
import CoreAudio
import CoreServices
import Foundation

// System actions and screenshots. All Process runs are async with a timeout.
enum SystemActionExecutor {
    static func perform(_ action: SystemAction) {
        switch action {
        case .spotlight:
            KeyPress.key(49, .maskCommand)
        case .mediaPlayPause:
            KeyPress.mediaKey(16)
        case .mediaNext:
            KeyPress.mediaKey(17)
        case .mediaPrevious:
            KeyPress.mediaKey(18)
        case .startScreenSaver:
            DispatchQueue.main.async {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"))
            }
        case .lockScreen:
            KeyPress.key(12, [.maskControl, .maskCommand])
        case .sleepDisplay:
            systemQueue.async {
                WatchedProcess.run(path: "/usr/bin/pmset", args: ["displaysleepnow"],
                                   cwd: FileManager.default.homeDirectoryForCurrentUser,
                                   label: "sleepDisplay")
            }
        case .sleepSystem:
            systemQueue.async {
                WatchedProcess.run(path: "/usr/bin/pmset", args: ["sleepnow"],
                                   cwd: FileManager.default.homeDirectoryForCurrentUser,
                                   label: "sleepSystem")
            }
        case .logOut:
            systemQueue.async {
                guard confirmed(title: "Log Out?",
                                message: "Log out of your Mac now? Open apps will be asked to save.",
                                actionLabel: "Log Out") else { return }
                DispatchQueue.main.async { sendLoginwindowEvent(eventLogOut) }
            }
        case .restart:
            systemQueue.async {
                guard confirmed(title: "Restart?",
                                message: "Restart your Mac now? Open apps will be asked to save.",
                                actionLabel: "Restart") else { return }
                DispatchQueue.main.async { sendLoginwindowEvent(eventRestart) }
            }
        case .shutDown:
            systemQueue.async {
                guard confirmed(title: "Shut Down?",
                                message: "Shut down your Mac now? Open apps will be asked to save.",
                                actionLabel: "Shut Down") else { return }
                DispatchQueue.main.async { sendLoginwindowEvent(eventShutDown) }
            }
        case .ejectAllDisks:
            systemQueue.async { ejectAllDisks() }
        case .emptyTrash:
            systemQueue.async { emptyTrash() }
        case .openTrash:
            DispatchQueue.main.async {
                NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash"))
            }
        case .hideOtherApps:
            DispatchQueue.main.async {
                NSWorkspace.shared.hideOtherApplications()
            }
        case .quitAllApps:
            quitApps(exceptFrontmost: false)
        case .quitAllExceptFrontmost:
            quitApps(exceptFrontmost: true)
        case .restartFrontmostApp:
            restartFrontmostApp()
        case .toggleHiddenFiles:
            systemQueue.async { toggleHiddenFiles() }
        case .toggleMute:
            systemQueue.async { toggleMute() }
        case .toggleStageManager:
            systemQueue.async { toggleStageManager() }
        case .toggleAppearance:
            systemQueue.async { toggleAppearance() }
        }
    }

    // MARK: - Confirmation

    /// Modal Are-you-sure on the main thread. perform() runs on background
    /// queues, so blocking here is safe. Activates the app first so the
    /// alert fronts even when running as a background accessory.
    private static func confirmed(title: String, message: String, actionLabel: String) -> Bool {
        MainThread.value {
            NSApplication.shared.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: actionLabel)
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn
        }
    }

    /// Non-blocking info note on the main thread (fire-and-forget).
    private static func notify(title: String, message: String) {
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    // MARK: - Power (loginwindow AppleEvents, Apple QA1134)

    // Event class 'aevt' sent to the loginwindow system process: cancellable
    // by apps, no Automation prompt. Our own alert confirms first (above).
    private static let loginwindowClass = AEEventClass(0x61657674) // 'aevt'
    private static let eventLogOut = AEEventID(0x726c676f) // 'rlgo' kAEReallyLogOut
    private static let eventRestart = AEEventID(0x72657374) // 'rest' kAERestart
    private static let eventShutDown = AEEventID(0x73687574) // 'shut' kAEShutDown

    // AESend is declared in Carbon/HIToolbox (AEInteraction.h), which has no
    // Swift module in explicit-modules builds: bind the C symbol directly.
    // CoreServices (imported above) re-exports AE, so it links.
    @_silgen_name("AESend")
    private static func carbonSendEvent(_ appleEvent: UnsafePointer<AppleEvent>,
                                        _ reply: UnsafeMutablePointer<AppleEvent>?,
                                        _ sendMode: AESendMode,
                                        _ sendPriority: AESendPriority,
                                        _ timeoutInTicks: Int32,
                                        _ idleProc: UnsafeRawPointer?,
                                        _ filterProc: UnsafeRawPointer?) -> OSErr

    private static func sendLoginwindowEvent(_ eventID: AEEventID) {
        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: 1) // kSystemProcess
        var target = AEAddressDesc()
        let targetErr = withUnsafePointer(to: &psn) { psnPtr in
            AECreateDesc(typeProcessSerialNumber, psnPtr, MemoryLayout<ProcessSerialNumber>.size, &target)
        }
        guard targetErr == noErr else {
            print("PowerAction: target failed (\(targetErr))")
            return
        }
        defer { AEDisposeDesc(&target) }
        var event = AppleEvent()
        let createErr = AECreateAppleEvent(loginwindowClass, eventID, &target,
                                           AEReturnID(kAutoGenerateReturnID),
                                           AETransactionID(kAnyTransactionID), &event)
        guard createErr == noErr else {
            print("PowerAction: create failed (\(createErr))")
            return
        }
        defer { AEDisposeDesc(&event) }
        let sendErr = carbonSendEvent(&event, nil, AESendMode(kAENoReply), AESendPriority(kAENormalPriority), Int32(kAEDefaultTimeout), nil, nil)
        if sendErr != noErr {
            print("PowerAction: send failed (\(sendErr))")
        }
    }

    // MARK: - Disks and Trash

    /// Mountpoints safe to eject: local, non-internal, not the boot volume.
    /// NSURL's volumeIsEjectable lies for APFS (false on external APFS
    /// volumes), so filter on internal/local only and let `diskutil eject`
    /// resolve whole-disk eject per mountpoint.
    private static func ejectCandidates() -> [String] {
        let fm = FileManager.default
        var out: [String] = []
        for name in (try? fm.contentsOfDirectory(atPath: "/Volumes")) ?? [] {
            if name == ".timemachine" { continue }
            let path = "/Volumes/" + name
            let url = URL(fileURLWithPath: path)
            guard let values = try? url.resourceValues(forKeys: [.volumeIsInternalKey,
                                                                 .volumeIsLocalKey]) else { continue }
            if values.volumeIsInternal == true { continue }
            if values.volumeIsLocal == false { continue }
            // The startup volume shows up in /Volumes as a symlink to / —
            // never offer to eject it (covers external-boot Macs too).
            if url.resolvingSymlinksInPath().path == "/" { continue }
            out.append(path)
        }
        return out.sorted()
    }

    private static func ejectAllDisks() {
        let candidates = ejectCandidates()
        guard !candidates.isEmpty else {
            notify(title: "Nothing to Eject", message: "No external disks are connected.")
            return
        }
        let list = candidates.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        guard confirmed(title: "Eject \(candidates.count) Disk\(candidates.count == 1 ? "" : "s")?",
                        message: "Eject \(list)?",
                        actionLabel: "Eject All") else { return }
        for path in candidates {
            WatchedProcess.run(path: "/usr/sbin/diskutil", args: ["eject", path],
                               cwd: FileManager.default.homeDirectoryForCurrentUser,
                               label: "eject")
        }
    }

    private static func trashDirs() -> [URL] {
        let fm = FileManager.default
        var dirs = [fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")]
        if let volumes = try? fm.contentsOfDirectory(atPath: "/Volumes") {
            let uid = getuid()
            for name in volumes {
                dirs.append(URL(fileURLWithPath: "/Volumes/\(name)/.Trashes/\(uid)"))
            }
        }
        return dirs
    }

    private static func emptyTrash() {
        let fm = FileManager.default
        let items = trashDirs().flatMap {
            (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? []
        }
        guard !items.isEmpty else {
            notify(title: "Trash Is Empty", message: "There is nothing to delete.")
            return
        }
        guard confirmed(title: "Empty Trash?",
                        message: "Permanently delete \(items.count) item\(items.count == 1 ? "" : "s")? This cannot be undone.",
                        actionLabel: "Empty Trash") else { return }
        for item in items {
            try? fm.setAttributes([.immutable: false], ofItemAtPath: item.path)
            do {
                try fm.removeItem(at: item)
            } catch {
                print("EmptyTrash: \(item.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - App control

    private static func quitTargets(exceptFrontmost: Bool) -> [NSRunningApplication] {
        let me = NSRunningApplication.current.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular else { return false }
            guard app.processIdentifier != me else { return false }
            guard app.bundleIdentifier != "com.apple.finder" else { return false }
            if exceptFrontmost, let front, app.processIdentifier == front { return false }
            return true
        }
    }

    private static func quitApps(exceptFrontmost: Bool) {
        systemQueue.async {
            let snapshot = MainThread.value { quitTargets(exceptFrontmost: exceptFrontmost) }
            guard !snapshot.isEmpty else {
                notify(title: "Nothing to Quit", message: "There are no other apps running.")
                return
            }
            let names = snapshot.prefix(4).compactMap { $0.localizedName }
            var detail = names.joined(separator: ", ")
            if snapshot.count > names.count {
                detail += " and \(snapshot.count - names.count) more"
            }
            detail += ". Unsaved work will prompt per app."
            let title = exceptFrontmost ? "Quit All Apps Except Frontmost?" : "Quit All Apps?"
            guard confirmed(title: title, message: "Quit \(detail)", actionLabel: "Quit All") else { return }
            DispatchQueue.main.async {
                for app in quitTargets(exceptFrontmost: exceptFrontmost) where !app.terminate() {
                    print("QuitApps: \(app.localizedName ?? "?") refused terminate")
                }
            }
        }
    }

    private static func restartFrontmostApp() {
        systemQueue.async {
            guard let target = MainThread.value({
                NSWorkspace.shared.frontmostApplication.flatMap { app in
                    guard app.bundleIdentifier != "com.apple.finder",
                          let url = app.bundleURL,
                          let name = app.localizedName else { return nil as (NSRunningApplication, URL, String)? }
                    return (app, url, name)
                }
            }) else {
                print("RestartApp: nothing restartable (Finder excluded)")
                return
            }
            // An app cannot relaunch itself: terminate() would kill this
            // process mid-queue and the relaunch below would never fire.
            if target.0.processIdentifier == NSRunningApplication.current.processIdentifier {
                notify(title: "Cannot Restart LaunchCorner",
                       message: "This action cannot restart LaunchCorner itself. Quit and reopen it manually if needed.")
                return
            }
            guard confirmed(title: "Restart \(target.2)?",
                            message: "\(target.2) will quit and reopen. Unsaved work will prompt first.",
                            actionLabel: "Restart") else { return }
            let (app, url, name) = target
            let fired = MainThread.value { app.terminate() }
            guard fired else {
                print("RestartApp: \(name) refused terminate")
                return
            }
            // Wait for the old pid to actually exit. Big apps can take
            // seconds (autosave/flush); isTerminated updates via workspace
            // notifications, kill(pid, 0) is the runloop-independent backstop
            // (stale isTerminated + short deadline = quit with no relaunch).
            let pid = app.processIdentifier
            let deadline = Date().addingTimeInterval(10.0)
            var exited = false
            while Date() < deadline {
                if app.isTerminated || kill(pid, 0) != 0 {
                    exited = true
                    break
                }
                Thread.sleep(forTimeInterval: 0.2)
            }
            guard exited else {
                print("RestartApp: pid \(pid) still alive after 10s (save dialog?), aborting relaunch")
                return
            }
            relaunchApp(at: url, label: name)
        }
    }

    private static func relaunchApp(at url: URL, label: String) {
        MainThread.value {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
                if let error {
                    // Never fail silently: /usr/bin/open outlives any API hiccup.
                    print("RestartApp: openApplication failed (\(error.localizedDescription)), trying /usr/bin/open")
                    WatchedProcess.run(path: "/usr/bin/open", args: [url.path],
                                       cwd: FileManager.default.homeDirectoryForCurrentUser,
                                       label: "relaunch")
                } else {
                    print("RestartApp: relaunched \(label) pid \(app?.processIdentifier ?? -1)")
                }
            }
        }
    }

    // MARK: - Toggles

    private static func toggleHiddenFiles() {
        let current = UserDefaults(suiteName: "com.apple.finder")?.bool(forKey: "AppleShowAllFiles") ?? false
        // Finder only re-reads at launch: single ordered shell line, then it relaunches.
        let flag = current ? "false" : "true"
        WatchedProcess.run(path: "/bin/sh",
                           args: ["-c", "defaults write com.apple.finder AppleShowAllFiles \(flag) && killall Finder"],
                           cwd: FileManager.default.homeDirectoryForCurrentUser,
                           label: "hiddenFiles")
    }

    private static func toggleMute() {
        // CoreAudio mute on the default output device: in-process, no TCC.
        var deviceAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                    mScope: kAudioObjectPropertyScopeGlobal,
                                                    mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectHasProperty(AudioObjectID(kAudioObjectSystemObject), &deviceAddr),
              AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &deviceAddr,
                                            0, nil, &deviceSize, &device) == noErr,
              device != kAudioObjectUnknown else {
            print("Mute: no output device")
            return
        }
        var muteAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                  mScope: kAudioDevicePropertyScopeOutput,
                                                  mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &muteAddr) else {
            print("Mute: device has no mute control")
            return
        }
        var muted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &muteAddr, 0, nil, &muteSize, &muted) == noErr else {
            print("Mute: could not read mute state")
            return
        }
        var next: UInt32 = muted == 0 ? 1 : 0
        let err = AudioObjectSetPropertyData(device, &muteAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &next)
        if err != noErr {
            print("Mute: set failed (\(err))")
        }
    }

    private static func toggleStageManager() {
        // macOS 13+. WindowManager re-reads at launch: ordered line + relaunch.
        let current = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
        let flag = current ? "false" : "true"
        WatchedProcess.run(path: "/bin/sh",
                           args: ["-c", "defaults write com.apple.WindowManager GloballyEnabled -bool \(flag) && killall WindowManager"],
                           cwd: FileManager.default.homeDirectoryForCurrentUser,
                           label: "stageManager")
    }

    private static func toggleAppearance() {
        // SkyLight private SPI + prefs + distributed notification: no
        // Automation prompt (the AppleScript path would need one).
        let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        let nextDark = !dark
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let sym = dlsym(handle, "SLSSetAppearanceThemeLegacy") else {
            print("Appearance: SkyLight unavailable")
            return
        }
        defer { dlclose(handle) }
        typealias SLSFn = @convention(c) (Bool) -> Void
        unsafeBitCast(sym, to: SLSFn.self)(nextDark)
        if nextDark {
            CFPreferencesSetValue("AppleInterfaceStyle" as CFString, "Dark" as CFString,
                                  kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        } else {
            CFPreferencesSetValue("AppleInterfaceStyle" as CFString, nil,
                                  kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        }
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDistributedCenter(),
                                             CFNotificationName("AppleInterfaceThemeChangedNotification" as CFString),
                                             nil, nil, true)
    }

    private static let systemQueue = DispatchQueue(label: "com.launchcorner.system")
    // Monotonic per-process counter: same-millisecond bursts can't collide.
    // (All mutations happen on systemQueue.)
    private static var shotCounter: UInt = 0

    static func screenshot(kind: ScreenshotKind, destination: ScreenshotDestination, directory: String) {
        // Screen Recording TCC gates the CALLING app: preflight first so the
        // system prompts instead of failing silently. Without a grant the
        // capture comes out blank — skip loudly and tell the user where to enable it.
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            print("Screenshot: needs Screen Recording access (System Settings > Privacy & Security > Screen Recording). Capture skipped.")
            return
        }
        var args: [String] = []
        switch kind {
        case .full:
            break
        case .selection:
            args.append("-i")
        case .window:
            // Front window directly; -iw would wait for a manual click instead.
            args.append("-w")
        }
        switch destination {
        case .clipboard:
            args.append("-c")
        case .file:
            let expanded = (directory as NSString).expandingTildeInPath
            let dirURL = URL(fileURLWithPath: expanded, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            } catch {
                print("Screenshot: failed to create directory \(expanded): \(error.localizedDescription)")
                return
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let stamp = formatter.string(from: Date())
            // Millisecond + pid + counter suffix: bursts can't collide.
            let unique = "\(stamp)-\(UInt64(Date().timeIntervalSince1970 * 1000) % 100000)-\(ProcessInfo.processInfo.processIdentifier)"
            let fileURL = dirURL.appendingPathComponent("Screenshot-\(unique).png")
            args.append(fileURL.path)
        }
        let finalArgs = args
        systemQueue.async {
            shotCounter += 1
            var namespaced = finalArgs
            if let last = namespaced.last, last.hasSuffix(".png") {
                let base = (last as NSString).deletingPathExtension
                namespaced[namespaced.count - 1] = "\(base)-\(shotCounter).png"
            }
            WatchedProcess.run(path: "/usr/sbin/screencapture", args: namespaced,
                               cwd: FileManager.default.homeDirectoryForCurrentUser,
                               label: "screencapture")
        }
    }
}
