# Mindow

A keyboard-driven window manager for macOS that keeps your Spectacle shortcuts.

[Spectacle](https://github.com/eczarny/spectacle) was archived in 2019. Mindow aims to cover its 18 actions,
cycle sizes when the same shortcut is pressed again, and import an existing Spectacle `Shortcuts.json`.

> Status: early development. Nothing to install yet.

## Development

Requires Xcode 16 or later on macOS 14+.

```sh
swift test --package-path MindowCore   # window math and parsing
xcodegen generate                      # after editing project.yml
xcodebuild -project Mindow.xcodeproj -scheme Mindow build
```

Window geometry and shortcut parsing live in `MindowCore` and are covered by tests.
The app target only talks to the Accessibility API and draws UI.

## License

MIT
