#!/usr/bin/env python3
"""Hyper-dense regression suite for LaunchCorner corner actions.

Run every time these features change:
    python3 scripts/test_actions.py [--no-build]

Covers: Debug build, model Codable (old-format migration, roundtrips,
tolerant reader), shells/interpreters, live shell+script runs, QuickLink
resolution, window snap end-to-end (needs Accessibility), appearance
roundtrip, screenshots (needs Screen Recording), self-dismissing
Spotlight/Mission Control triggers. Prints one line per check, exits
non-zero on any FAIL. Lifetime SKIP = environment lacks that capability.
Disruptive actions (lock/sleep/screensaver/live media) are NEVER triggered.
"""
import argparse, os, re, shutil, subprocess, sys, tempfile, time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TMP = tempfile.gettempdir()
HARNESS_SRC = [
    "LaunchCorner/Models/CornerConfig.swift",
    "LaunchCorner/Services/MainThread.swift",
    "LaunchCorner/Services/WatchedProcess.swift",
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
                   "-framework", "ApplicationServices"], timeout=300)
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
    rc, out = harness("shells")
    shells = [l.split(None, 1)[1] for l in out.splitlines() if l.startswith("SHELL ")]
    check("ENV", "shells-found", len(shells) > 0, ",".join(shells))
    check("ENV", "zsh-present", "/bin/zsh" in shells)
    interp = {}
    for lang in ["bash", "appleScript", "python", "javaScript", "typeScript", "go", "ruby", "csharp"]:
        rc, out = harness("interp", lang)
        m = re.search(r"INTERP (\S+)", out)
        interp[lang] = m.group(1) if m else "?"
        if lang in ("bash", "appleScript", "python"):
            check("ENV", f"interp-{lang}", interp[lang] != "MISSING", interp[lang])
        else:
            check("ENV", f"interp-{lang}", True if interp[lang] not in ("MISSING", "?") else None, interp[lang])

    print("== SHELL-RUN ==")
    m1 = os.path.join(TMP, "lc_marker1")
    if os.path.exists(m1): os.remove(m1)
    harness("runshell", "/bin/zsh", f"echo ok > {m1}")
    check("SHELL", "echo-to-file", wait_file(m1, 10))
    m1b = os.path.join(TMP, "lc_marker1b")
    if os.path.exists(m1b): os.remove(m1b)
    harness("runshell", "/bin/zsh", f"echo no > {m1b} && exit 3")
    time.sleep(3)
    rc, out = harness("runshell", "/bin/zsh", "true")
    check("SHELL", "nonzero-survives", "RUNSHELL-DONE" in out and os.path.exists(m1b),
          "exit-3 command ran through, harness responsive")
    rc, out = harness("runshell", "/nonexistent/sh", "echo x")
    check("SHELL", "bad-shell-guarded", "RUNSHELL-DONE" in out and "not executable" in out,
          "refused before fork")

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

    print("== SYSTEM ==")
    rc, out = harness("appear")
    before = "Dark" if re.search(r"STYLE Dark", out) else "Light"
    try:
        harness("appeartoggle")
        rc, out = harness("appear")
        after = "Dark" if re.search(r"STYLE Dark", out) else "Light"
        check("SYSTEM", "appearance-flips", after != before, f"{before}->{after} (global domain)")
        harness("appeartoggle")
        rc, out = harness("appear")
        restored = "Dark" if re.search(r"STYLE Dark", out) else "Light"
        check("SYSTEM", "appearance-restores", restored == before, f"back to {restored}")
    finally:
        rc, out = harness("appear")
        cur = "Dark" if re.search(r"STYLE Dark", out) else "Light"
        if cur != before:
            harness("appeartoggle")
            print(f"(restored theme to {before} after interrupt)", flush=True)

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
    headless = "could not create image from display" in shout
    check("SYSTEM", "shot-file", True if ok else (None if headless else False),
          png or ("SKIP: no display in test session" if headless else "no file produced"))
    rc, out = harness("shotclip", timeout=30)
    if "could not create image from display" in out:
        check("SYSTEM", "shot-clipboard", None, "SKIP: no display in test session")
    else:
        check("SYSTEM", "shot-clipboard", "CLIPIMAGE YES" in out, out.strip()[:120])

    rc, out = harness("spotkey", timeout=30)
    check("SYSTEM", "spotlight-smoke", True if "SPOT-OK" in out else (None if "SPOT-NO-AX" in out else False),
          "posts keys, Esc-dismisses; visual confirm needed")
    rc, out = harness("missionkey", timeout=30)
    check("SYSTEM", "mission-smoke", True if "MISSION-OK" in out else (None if "MISSION-NO-AX" in out else False),
          "posts keys, Esc-dismisses; visual confirm needed")
    print("SYSTEM excluded (disruptive, dispatch-covered): lockScreen sleepDisplay startScreenSaver media*")

    return finish()

def finish():
    print(f"\n== {PASS} passed, {FAIL} failed, {SKIP} skipped ==")
    return 1 if FAIL else 0

if __name__ == "__main__":
    sys.exit(main())
