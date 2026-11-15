import KeyboardShortcuts
import MindowCore

/// Names are Spectacle's action names, so UserDefaults keys read `KeyboardShortcuts_MoveToLeftHalf`.
/// Spectacle's defaults are the initial shortcuts because this app exists to keep them.
@MainActor
enum Shortcuts {
    static let names: [WindowAction: KeyboardShortcuts.Name] = Dictionary(
        uniqueKeysWithValues: WindowAction.allCases.map { action in
            (action, KeyboardShortcuts.Name(action.rawValue, initial: SpectacleShortcuts.defaults[action].map(shortcut)))
        }
    )

    static func register(_ handler: @escaping @MainActor (WindowAction) -> Void) {
        for (action, name) in names {
            KeyboardShortcuts.onKeyDown(for: name) { handler(action) }
        }
    }

    /// Registration that failed earlier is dropped, so enabling again retries it
    /// without adding a second handler.
    static func reregister() {
        KeyboardShortcuts.enable(Array(names.values))
    }

    static func apply(_ bindings: [WindowAction: KeyBinding]) {
        for (action, binding) in bindings {
            guard let name = names[action] else { continue }
            KeyboardShortcuts.setShortcut(shortcut(binding), for: name)
        }
    }

    nonisolated static func shortcut(_ binding: KeyBinding) -> KeyboardShortcuts.Shortcut {
        .init(carbonKeyCode: binding.carbonKeyCode, carbonModifiers: binding.carbonModifiers)
    }
}
