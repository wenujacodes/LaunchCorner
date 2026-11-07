#!/usr/bin/env python3
"""Hyper-dense regression suite for LaunchCorner corner actions.

Run every time these features change:
    python3 scripts/test_actions.py [--no-build]

Covers: Debug build, model Codable (old-format migration, roundtrips,
tolerant reader, removed-case degradation), interpreters, live script runs,
QuickLink resolution, window snap end-to-end (needs Accessibility),
screenshots (needs Screen Recording), self-dismissing Spotlight trigger.
Prints one line per check, exits non-zero on any FAIL. Lifetime SKIP =
environment lacks that capability. Disruptive actions (lock/sleep/screensaver/
live media) are NEVER triggered.
"""
import argparse, os, re, shutil, subprocess, sys, tempfile, time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TMP = tempfile.gettempdir()
HARNESS_SRC = [
    "LaunchCorner/Models/CornerConfig.swift",
    "LaunchCorner/Services/MainThread.swift",
    "LaunchCorner/Services/WatchedProcess.swift",
    "LaunchCorner/Services/ShortcutExecutor.swift",
    "LaunchCorner/Services/KeyPress.swift",
    "LaunchCorner/Services/QuickLinkExecutor.swift",
    "LaunchCorner/Services/ShellExecutor.swift",
    "LaunchCorner/Services/WindowSnapExecutor.swift",
    "LaunchCorner/Services/SystemActionExecutor.swift",
    "LaunchCorner/Services/ActionExecutor.swift",
    "scripts/test_harness.swift",
]
HARNESS_BIN = os.path.join(TMP, "lc_harness")
PASS = FAIL = SKIP = 0

def check(section, name, ok, detail=""):
    global PASS, FAIL, SKIP
    tag = "PASS" if ok is True else ("FAIL" if ok is False else "SKIP")
    if ok is True: PASS += 1
    elif ok is False: FAIL += 1
    else: SKIP += 1
    print(f"[{section}] {tag} {name}" + (f" — {detail}" if detail else ""), flush=True)

def run(cmd, timeout=120, cwd=REPO):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=cwd)
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except subprocess.TimeoutExpired:
        return 124, "TIMEOUT"

def harness(*a, timeout=60):
    return run([HARNESS_BIN] + list(a), timeout=timeout)

def wait_file(path, timeout=15):
    t0 = time.time()
    while time.time() - t0 < timeout:
        if os.path.exists(path) and os.path.getsize(path) > 0:
            return True
        time.sleep(0.2)
    return os.path.exists(path)

def newest_png(d):
    cands = [(os.path.getmtime(os.path.join(d, f)), f) for f in os.listdir(d)
             if f.endswith(".png") and os.path.join(d, f) not in newest_png.seen]
    return max(cands)[1] if cands else None
newest_png.seen = set()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-build", action="store_true")
    args = ap.parse_args()

    if not args.no_build:
        print("== BUILD ==")
        rc, out = run(["xcodebuild", "build", "-project", "LaunchCorner.xcodeproj",
                       "-scheme", "LaunchCorner", "-configuration", "Debug",
                       "-destination", "platform=macOS", 'ARCHS=arm64'], timeout=600)
        check("BUILD", "debug-build", rc == 0, out.strip().splitlines()[-1] if out else "")
        if rc != 0:
            return finish()
    else:
        print("== BUILD skipped ==")

    print("== HARNESS ==")
    sdk = subprocess.run(["xcrun", "--sdk", "macosx", "--show-sdk-path"],
                         capture_output=True, text=True).stdout.strip()
    rc, out = run(["xcrun", "swiftc"] + HARNESS_SRC + ["-o", HARNESS_BIN,
                   "-sdk", sdk, "-framework", "AppKit",
                   "-framework", "ApplicationServices",
                   "-framework", "CoreServices",
                   "-framework", "CoreAudio",
                   "-framework", "Carbon"], timeout=300)
    check("HARNESS", "compile", rc == 0, out.strip()[:300])
    if rc != 0:
        return finish()

    print("== MODEL ==")
    rc, out = harness("model")
    n = 0
    for line in out.splitlines():
        m = re.match(r"MODEL (\S+) (PASS|FAIL) ?(.*)", line)
        if m:
            n += 1
            check("MODEL", m.group(1), m.group(2) == "PASS", m.group(3))
    check("MODEL", "harness-ran", n > 15, f"{n} checks")

    print("== ENV ==")
    interp = {}
    for lang in ["bash", "appleScript", "python", "javaScript", "typeScript", "go", "ruby", "csharp"]:
        rc, out = harness("interp", lang)
        m = re.search(r"INTERP (\S+)", out)
        interp[lang] = m.group(1) if m else "?"
        if lang in ("bash", "appleScript", "python"):
            check("ENV", f"interp-{lang}", interp[lang] != "MISSING", interp[lang])
        else:
            check("ENV", f"interp-{lang}", True if interp[lang] not in ("MISSING", "?") else None, interp[lang])

    print("== SCRIPT-RUN ==")
    scripts = {
        "bash": ("#!/bin/bash\necho ok > %s\n" % os.path.join(TMP, "lc_mbash"), "lc_t.sh", "lc_mbash"),
        "python": ("print(open('%s','w').write('ok'))\n" % os.path.join(TMP, "lc_mpy"), "lc_t.py", "lc_mpy"),
        "appleScript": ('do shell script "echo ok > %s"\n' % os.path.join(TMP, "lc_mscpt"), "lc_t.scpt", "lc_mscpt"),
    }
    for lang, (body, fname, marker) in scripts.items():
        if interp.get(lang) in (None, "MISSING", "?"):
            check("SCRIPT", lang, None, "no interpreter")
            continue
        p = os.path.join(TMP, fname)
        open(p, "w").write(body)
        mp = os.path.join(TMP, marker)
        if os.path.exists(mp): os.remove(mp)
        harness("runscript", lang, p)
        check("SCRIPT", lang, wait_file(mp, 12), interp[lang])

    print("== QUICKLINK ==")
    cases = [
        ("https://example.com", "https", False),
        ("shortcuts://run-shortcut?name=My Shortcut", "shortcuts", False),
        ("~/Downloads", None, True),
        ("/tmp/x.txt", None, True),
    ]
    for raw, scheme, isfile in cases:
        rc, out = harness("ql", raw)
        m = re.search(r"QL scheme=(\S+) isFile=(\S+)", out)
        ok = bool(m) and (m.group(1) == scheme if scheme else True) and (m.group(2) == ("true" if isfile else "false"))
        check("QUICKLINK", f"resolve:{raw[:40]}", ok, out.strip()[:90])
    if os.path.exists("/usr/bin/shortcuts"):
        check("QUICKLINK", "shortcuts-cli", True)
    else:
        check("QUICKLINK", "shortcuts-cli", None, "no /usr/bin/shortcuts on this Mac")

    print("== SNAP ==")
    rc, out = harness("ax")
    trusted = "AX YES" in out
    check("SNAP", "ax-trusted", True if trusted else None, out.strip())
    if trusted:
        rc, out = harness("snaptest", timeout=90)
        m = re.search(r"SNAP left=(PASS|FAIL) quarter=(PASS|FAIL)", out)
        if m:
            check("SNAP", "left-half", m.group(1) == "PASS", out.strip()[:200])
            check("SNAP", "quarter", m.group(2) == "PASS", out.strip()[:200])
        else:
            check("SNAP", "end-to-end", None if "SKIP" in out else False, out.strip()[:200])
        # Off-main caller: pre-fix this crashed inside AX setAttributeValue.
        # Main thread pumps a runloop while waiting (bg work hops to main).
        rc, out = harness("snaptest-bg", timeout=150)
        m = re.search(r"SNAP left=(PASS|FAIL) quarter=(PASS|FAIL)", out)
        if m:
            check("SNAP", "bg-caller-safe", m.group(1) == "PASS" and m.group(2) == "PASS" and "SNAPBG-DONE" in out, out.strip()[:200])
        else:
            check("SNAP", "bg-caller-safe", None if "SKIP" in out else False, out.strip()[:200])

    print("== MTC ==")
    import glob as _glob
    mtc = None
    for cand in _glob.glob("/Applications/Xcode*.app/Contents/Developer/usr/lib/libMainThreadChecker.dylib"):
        mtc = cand
        break
    if mtc and trusted:
        env = dict(os.environ, DYLD_INSERT_LIBRARIES=mtc)
        try:
            p = subprocess.run([HARNESS_BIN, "snaptest-bg"], capture_output=True, text=True,
                               timeout=150, cwd=REPO, env=env)
            hit = "Main Thread Checker" in (p.stdout + p.stderr)
            check("MTC", "no-main-thread-violation", not hit,
                  "clean under libMainThreadChecker" if not hit else (p.stdout + p.stderr)[-500:])
        except subprocess.TimeoutExpired:
            check("MTC", "no-main-thread-violation", False, "TIMEOUT (possible deadlock)")
    else:
        check("MTC", "no-main-thread-violation", None, "no dylib or no AX trust")

    print("== FUZZ ==")
    rc, out = harness("fuzz", timeout=120)
    m = re.search(r"FUZZ actions=(\d+) nonNone=(\d+) configs=(\d+)/(\d+)", out)
    check("FUZZ", "no-crash-tolerant", bool(m) and rc == 0, out.strip()[:160])

    print("== SCAN ==")
    import pathlib as _pl
    svc = _pl.Path(REPO, "LaunchCorner")
    hits = []
    for f in list((svc / "Services").glob("*.swift")) + list((svc / "Models").glob("*.swift")):
        text = f.read_text()
        for i, line in enumerate(text.splitlines(), 1):
            s = line.strip()
            if s.startswith("//"):
                continue
            if "DispatchQueue.main.sync" in s and f.name != "MainThread.swift":
                hits.append((f.name, i, "main.sync (deadlock-prone)"))
            if re.search(r"\bas!|\btry!", s):
                hits.append((f.name, i, "force-unwrap"))
    for f in (svc / "Services").glob("*.swift"):
        if f.name in ("WatchedProcess.swift", "PermissionManager.swift"):
            continue
        text = f.read_text()
        for i, line in enumerate(text.splitlines(), 1):
            if line.strip().startswith("//"):
                continue
            if "Process()" in line:
                hits.append((f.name, i, "raw Process() outside WatchedProcess"))
    for f in (svc / "Services").glob("*.swift"):
        if f.name == "WindowSnapExecutor.swift":
            continue
        text = f.read_text()
        for i, line in enumerate(text.splitlines(), 1):
            if line.strip().startswith("//"):
                continue
            if "AXUIElementSetAttributeValue" in line:
                hits.append((f.name, i, "AX set outside snap (main-thread risk)"))
    check("SCAN", "static-tripewires", len(hits) == 0, "; ".join(f"{a}:{b} {c}" for a, b, c in hits[:8]))

    print("== SYSTEM ==")
    shotdir = os.path.join(TMP, "lc_shots")
    os.makedirs(shotdir, exist_ok=True)
    for f in os.listdir(shotdir):
        newest_png.seen.add(os.path.join(shotdir, f))
    rc, shout = harness("shot", "full", "file", shotdir, timeout=40)
    png = None
    t0 = time.time()
    while time.time() - t0 < 20 and png is None:
        png = newest_png(shotdir)
        if png is None: time.sleep(0.5)
    ok = png is not None and os.path.getsize(os.path.join(shotdir, png)) > 0
    # "could not create image from display" = headless test session, not app code
    # (real login sessions capture fine, subject to Screen Recording TCC).
    # "needs Screen Recording access" = session lacks the TCC grant (also env).
    headless = "could not create image from display" in shout or "needs Screen Recording access" in shout
    check("SYSTEM", "shot-file", True if ok else (None if headless else False),
          png or ("SKIP: no Screen Recording grant in test session" if headless else "no file produced"))
    rc, out = harness("shotclip", timeout=30)
    if "could not create image from display" in out or "needs Screen Recording access" in out:
        check("SYSTEM", "shot-clipboard", None, "SKIP: no Screen Recording grant in test session")
    else:
        check("SYSTEM", "shot-clipboard", "CLIPIMAGE YES" in out, out.strip()[:120])

    rc, out = harness("spotkey", timeout=30)
    check("SYSTEM", "spotlight-smoke", True if "SPOT-OK" in out else (None if "SPOT-NO-AX" in out else False),
          "posts keys, Esc-dismisses; visual confirm needed")
    print("SYSTEM excluded (disruptive, dispatch-covered): lockScreen sleepDisplay sleepSystem logOut restart shutDown startScreenSaver media* ejectAllDisks emptyTrash openTrash hideOtherApps quitAll* restartFrontmostApp toggle*")

    return finish()

def finish():
    print(f"\n== {PASS} passed, {FAIL} failed, {SKIP} skipped ==")
    return 1 if FAIL else 0

if __name__ == "__main__":
    sys.exit(main())
