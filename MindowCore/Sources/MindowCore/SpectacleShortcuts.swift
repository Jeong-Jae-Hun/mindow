import Foundation

public enum SpectacleShortcuts {
    public struct ImportResult: Equatable, Sendable {
        public var bindings: [WindowAction: KeyBinding]
        /// Entries Mindow cannot map, shown to the user instead of being dropped silently.
        public var skipped: [String]
    }

    /// Spectacle's own defaults. They also match the bundled `Shortcuts.json` fixture.
    public static let defaults = defaultBindings.compactMapValues { KeyBinding(spectacle: $0) }

    private static let defaultBindings: [WindowAction: String] = [
        .moveToLeftHalf: "alt+cmd+left", .moveToRightHalf: "alt+cmd+right",
        .moveToTopHalf: "alt+cmd+up", .moveToBottomHalf: "alt+cmd+down",
        .moveToUpperLeft: "ctrl+cmd+left", .moveToUpperRight: "ctrl+cmd+right",
        .moveToLowerLeft: "ctrl+shift+cmd+left", .moveToLowerRight: "ctrl+shift+cmd+right",
        .moveToNextThird: "ctrl+alt+right", .moveToPreviousThird: "ctrl+alt+left",
        .moveToFullscreen: "alt+cmd+f", .moveToCenter: "alt+cmd+c",
        .moveToNextDisplay: "ctrl+alt+cmd+right", .moveToPreviousDisplay: "ctrl+alt+cmd+left",
        .makeLarger: "ctrl+alt+shift+right", .makeSmaller: "ctrl+alt+shift+left",
        .undoLastMove: "alt+cmd+z", .redoLastMove: "alt+shift+cmd+z",
    ]

    public static let defaultFilePath = "Library/Application Support/Spectacle/Shortcuts.json"
    public static let bundleIdentifier = "com.divisiblebyzero.Spectacle"

    public static func parse(_ data: Data) throws -> ImportResult {
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        var result = ImportResult(bindings: [:], skipped: [])
        for entry in entries {
            guard let action = WindowAction(rawValue: entry.name),
                  let binding = entry.binding.flatMap({ KeyBinding(spectacle: $0) })
            else {
                result.skipped.append("\(entry.name): \(entry.binding ?? "none")")
                continue
            }
            result.bindings[action] = binding
        }
        return result
    }

    private struct Entry: Decodable {
        let name: String
        let binding: String?

        enum CodingKeys: String, CodingKey {
            case name = "shortcut_name"
            case binding = "shortcut_key_binding"
        }
    }
}
