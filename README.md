# LaunchCorner

[![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-blue.svg?style=flat&logo=apple)](https://www.apple.com/macos)
[![Swift 5.0](https://img.shields.io/badge/Swift-5.0-orange.svg?style=flat&logo=swift)](https://developer.apple.com/swift/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Apple Silicon](https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-brightgreen.svg)]()

**LaunchCorner** turns your screen corners into instant app shortcuts. Simply move your cursor to any screen corner to launch your favorite applications instantly. Built natively for macOS using SwiftUI.

---

## Why LaunchCorner?

With recent macOS updates, Apple removed the built-in Launchpad shortcut for hot corners. While great third-party alternatives exist (such as LaunchOS), many require paid upgrades just to unlock hot corner support for opening app launchers.

LaunchCorner was created as a 100% free, open-source utility so that anyone can trigger LaunchOS (or any application) instantly via hot corners without paywalls or subscriptions.

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

- **Instant Hot Corners**: Move your cursor to any of the 4 screen corners to trigger assigned applications.
- **Native & Ultra-Fast**: Built natively with Swift & SwiftUI for zero latency and minimal CPU/memory footprint.
- **Apple Silicon (arm64)**: Native architecture for **M1/M2/M3/M4** Macs.
- **Dwell Time & Sensitivity**: Fine-tune trigger response down to **0 ms (Instant)**.
- **Multi-Monitor Support**: Works seamlessly across multiple connected displays.
- **Menu Bar & Dock Modes**: Runs quietly in the macOS Menu Bar and automatically hides from the Dock when closed.
- **Open Source**: 100% free and open-source under the MIT license.

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
