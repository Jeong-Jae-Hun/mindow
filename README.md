# Mindow

A keyboard-driven window manager for macOS that keeps your Spectacle shortcuts.

[Spectacle](https://github.com/eczarny/spectacle) was archived in 2019. Mindow aims to cover its 18 actions,
cycle sizes when the same shortcut is pressed again, and import an existing Spectacle `Shortcuts.json`.

> Status: early development. Nothing to install yet.

## Development

Requires Xcode 16 or later on macOS 14+.

```sh
swift test --package-path MindowCore   # window geometry
xcodegen generate                      # after editing project.yml
xcodebuild -project Mindow.xcodeproj -scheme Mindow build
```

Pure logic (window geometry now, shortcut parsing later) lives in `MindowCore` and is covered by tests.
The app target is a menu bar shell for now; Accessibility calls and settings UI come next.

## License

MIT
