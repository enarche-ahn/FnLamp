[한국어](README-kr.md) | [English](README.md)

# FnLamp

> A native macOS app that lets you check and toggle the fn key mode right from the menu bar

<img src="FnLamp.png" width="50%" alt="FnLamp icon">

---

## Motivation

Changing the fn key behavior in macOS requires navigating through **System Settings → Keyboard → Keyboard Shortcuts → Function Keys** — multiple steps every time. And there's no way to tell which mode is currently active without actually pressing a key.

FnLamp solves both of these annoyances.

---

## Features

| Feature | Description |
|---------|-------------|
| **Menu bar indicator** | Two-row LED (`fn` / 🌞) shows the current mode at a glance |
| **Click to toggle** | Left-click the menu bar icon to switch modes instantly |
| **Global shortcut** | Toggle from anywhere with the default shortcut `⌃⌥⌘F` |
| **Customizable shortcut** | Right-click → Shortcut Settings to assign any key combination |
| **Transition popover** | A brief notification appears below the menu bar for 1 second on every mode change |
| **External change detection** | Automatically syncs the indicator if the mode is changed via System Settings or any other path |

### Reading the menu bar indicator

```
fn  🟢   ← Standard Function Keys mode (F1, F2, F3 …)
🌞  ⚫
```

```
fn  ⚫   ← Special Function Keys mode (brightness, volume, media controls …)
🌞  🟠
```

---

## Installation

> **Note**: No pre-built binary is provided.
> Please build the project yourself using the macOS and Xcode versions appropriate for your system.

### Requirements

- macOS 26 or later
- Xcode 26 or later

### Build from source

```bash
git clone https://github.com/your-username/FnLamp.git
cd FnLamp
open FnLamp.xcodeproj
```

In Xcode, choose **Product → Run** (`⌘R`) to run, or **Product → Archive** to build a release binary.

---

## Usage

1. Launch the app — a small indicator appears in the menu bar (no Dock icon).
2. **Left-click** → toggle fn mode immediately
3. **Right-click** (or `⌃+left-click`) → context menu
   - **Toggle fn** (`T`) — switch mode
   - **Refresh State** (`R`) — sync with any externally applied changes
   - **Shortcut Settings…** — reassign the global shortcut
   - **Quit** (`Q`)
4. Global shortcut `⌃⌥⌘F` — toggles the mode regardless of which app has focus

---

## Tech Stack

- **Language**: Swift 5
- **UI**: SwiftUI + AppKit (menu-bar-only accessory app, no Dock icon)
- **Global hotkey**: Carbon Event Manager (`RegisterEventHotKey`)
- **Applying settings**: `CFPreferences` + the `activateSettings` utility for immediate effect without a restart

---

## License

MIT © 2026 Kyle Ahn — see [LICENSE](LICENSE) for details
