# LaunchCorner

**LaunchCorner** turns your screen corners into instant actions. Move your cursor to any screen corner to launch apps, open links, run scripts, snap windows, trigger system actions, or take screenshots — instantly. Built natively for macOS using SwiftUI, with a Liquid Glass interface on macOS 26+.

---

## Why LaunchCorner?

With recent macOS updates, Apple removed the built-in Launchpad shortcut for hot corners. While great third-party alternatives exist (such as LaunchOS), many require paid upgrades just to unlock hot corner support for opening app launchers.

LaunchCorner was created as a free, open-source utility so that anyone can trigger LaunchOS (or any application) instantly via hot corners without paywalls or subscriptions.

---

## Screenshots

<div align="center">
  <h5>1. Onboarding & Accessibility Permission</h3>
  <img src="docs/screenshots/onboarding.png" alt="LaunchCorner Onboarding" width="600" />
  <br /><br />
  
  <h5>2. Main Corner Configuration</h3>
  <img src="docs/screenshots/main-interface.png" alt="LaunchCorner Main Interface" width="600" />
  <br /><br />
  
  <h5>3. Settings & Sensitivity Controls</h3>
  <img src="docs/screenshots/settings.png" alt="LaunchCorner Settings" width="600" />
</div>

---

## Key Features

- **Instant Hot Corners**: Move your cursor to any of the 4 screen corners to trigger apps, links, scripts, window snaps, system actions, or screenshots.
- **Native & Ultra-Fast**: Built natively with Swift & SwiftUI for zero latency and minimal CPU/memory footprint.
- **Apple Silicon (arm64)**: Native architecture for **M1/M2/M3/M4** Macs.
- **Dwell Time & Sensitivity**: Fine-tune trigger response down to **0 ms (Instant)**.
- **Multi-Monitor Support**: Works seamlessly across multiple connected displays.
- **Runs in the Background**: Starts silently at login and hides from the Dock when closed. Open the app anytime to show its window.
- **Open Source**: 100% free and open-source under the MIT license.

### Corner Actions

Each corner can trigger one of five action types (configured per corner, Liquid Glass UI on macOS 26+):

- **App** — launch any application.
- **Quick Link** — open a URL, `shortcuts://` Shortcut link, or file path, optionally with a specific app.
- **Command** — run a script file (Bash, AppleScript, Python, JavaScript, TypeScript, Go, Ruby, C#). Script interpreters other than the built-ins install via Homebrew (e.g. `brew install node`).
- **Window** — snap the front window to a half or quarter of the display. Requires Accessibility access (already required by the app).
- **System** — Spotlight, play/pause/next/previous track, screen saver, lock screen, sleep display, Application Windows, plus screenshots (fullscreen/selection/window → file or clipboard). Keyboard-based actions require Accessibility access; screenshots require Screen Recording access on first use.

> **Tip**: set the matching macOS system corner to — (*System Settings → Desktop & Dock → Hot Corners…*) so both actions don't fire at once. The app reminds you the first time you configure a corner.

### Quick Link usage

A Quick Link opens anything addressable: `https://…` URLs, file paths (`~/Downloads`), app deep links (`obsidian://…`, `mailto:…`), and Apple Shortcuts (`shortcuts://run-shortcut?name=My%20Shortcut` — use the exact Shortcut name; spaces are encoded automatically). Optionally pick an app to open it with.

### Script usage

Point a corner at a script file and pick its language (Bash, AppleScript, Python, JavaScript, TypeScript, Go, Ruby, C#). Scripts run headless in the background with a 30-second timeout; failures are logged to the Console. Missing interpreters are flagged in the sheet with install hints (e.g. `brew install node`).

---

## Installation

1. Download **`LaunchCorner.dmg`** from the latest [Release](https://github.com/wenujacodes/LaunchCorner/releases).
2. Double-click `LaunchCorner.dmg` to open the installer.
3. Drag **LaunchCorner** into your **Applications** folder.
4. Open **LaunchCorner** and grant **Accessibility Access** when prompted (*System Settings > Privacy & Security > Accessibility*).

> **Note**: On first launch, if prompted by macOS Gatekeeper, right-click `LaunchCorner.app` and choose **Open** (or click **Open Anyway** in *System Settings > Privacy & Security*).

---

## Building from Source

```bash
# Clone repository
git clone https://github.com/wenujacodes/LaunchCorner.git
cd LaunchCorner

# Open in Xcode
open LaunchCorner.xcodeproj
```

To generate the installer (`LaunchCorner.dmg`) locally:
```bash
./scripts/build_release.sh
```

---

## License

Distributed under the **MIT License**. Created by [@wenujacodes](https://github.com/wenujacodes).
