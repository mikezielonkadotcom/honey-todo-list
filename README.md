# Honey Todo List

A clean, native macOS app for viewing your ClickUp tasks. Skips the ClickUp UI clutter and just shows you what's due.

- **Today** — tasks due by end of today
- **Tomorrow** — tasks due by end of tomorrow
- **All Due** — every assigned task with a due date

Each tab can be toggled on/off in Preferences.

## Features

- Native AppKit + SwiftUI
- Menu bar icon (left-click to toggle window, right-click for menu)
- Optional dock icon (toggle in Preferences)
- API token stored in macOS Keychain
- One-click task completion
- Double-click a row to open the task in ClickUp

## Setup

1. Build the app:
   ```bash
   ./build.sh
   ```
2. Install:
   ```bash
   cp -r ".build/Honey Todo List.app" /Applications/
   ```
3. Launch and open Preferences. Paste a ClickUp **Personal API Token** (starts with `pk_`) — generate one at ClickUp → Settings → Apps → API Token.

## Why personal token, not OAuth?

ClickUp OAuth requires HTTPS redirect URIs, which is awkward for native desktop apps. Personal tokens never expire and are stored in your Keychain.

## Requirements

- macOS 14+
- Apple Silicon (built for `arm64-apple-macosx14.0`)
- Swift 6 toolchain

## Architecture

Modeled on [bigscoots-app](https://github.com/mikezielonkadotcom/bigscoots-app) — same status bar / dock policy / preferences pattern, but driving a SwiftUI task list instead of a webview.

```
Sources/
  main.swift                  # AppDelegate + main menu
  DockManager.swift           # show-in-dock toggle
  StatusBarController.swift   # menu bar icon
  TasksWindow.swift           # main NSWindow
  TasksView.swift             # SwiftUI task list
  TaskStore.swift             # ObservableObject
  ClickUpAPI.swift            # API client
  KeychainStore.swift         # token storage
  PreferencesWindow.swift     # settings UI
```

## License

MIT
