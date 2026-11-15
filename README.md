# Mindow

A keyboard-driven window manager for macOS that keeps your Spectacle shortcuts.

[Spectacle](https://github.com/eczarny/spectacle) was archived in 2019. Mindow aims to cover its 18 actions,
cycle sizes when the same shortcut is pressed again, and import an existing Spectacle `Shortcuts.json`.

> Status: all 18 actions, size cycling and Spectacle import are in. No signed release yet; build from source.

## Features

- Spectacle's 18 actions with Spectacle's default shortcuts: halves, corners, thirds, fullscreen, center,
  next/previous display, larger/smaller, undo/redo.
- Press a half or corner shortcut again to cycle its width through 1/2, 1/3 and 2/3.
- Settings: record shortcuts, toggle cycling, hide the menu bar icon, launch at login.
- Import from Spectacle reads `~/Library/Application Support/Spectacle/Shortcuts.json` and previews it before replacing.
- Warns while Spectacle is running, since both apps would claim the same keys.

Mindow needs Accessibility access (System Settings > Privacy & Security > Accessibility).

## Development

Requires Xcode 26 or later (Swift 6.2, needed by KeyboardShortcuts). The app runs on macOS 14+.

```sh
swift test --package-path MindowCore   # window math, cycling, history, import parsing
xcodegen generate                      # after editing project.yml
xcodebuild -project Mindow.xcodeproj -scheme Mindow build
```

Pure logic (window math, size cycling, undo history, Spectacle parsing) lives in `MindowCore` and is covered by tests.
The app target only talks to the Accessibility API, registers shortcuts and draws settings.
Dependencies are pinned in `project.yml` and `Package.resolved`.

## License

MIT
