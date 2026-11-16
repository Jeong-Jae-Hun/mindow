import KeyboardShortcuts
import MindowCore
import Observation

/// Names are Spectacle's action names, so UserDefaults keys read `KeyboardShortcuts_MoveToLeftHalf`.
/// Spectacle's defaults are the initial shortcuts because this app exists to keep them.
@MainActor
enum Shortcuts {
    static let names: [WindowAction: KeyboardShortcuts.Name] = Dictionary(
        uniqueKeysWithValues: WindowAction.allCases.map { action in
            (action, KeyboardShortcuts.Name(action.rawValue, initial: SpectacleShortcuts.defaults[action].map(shortcut)))
        }
    )
    /// Spectacle has no such action, so it has no default and an import never sets it.
    static let togglePause = KeyboardShortcuts.Name("TogglePause")
    static let pause = ShortcutPause()

    static func register(_ handler: @escaping @MainActor (WindowAction) -> Void) {
        for (action, name) in names {
            KeyboardShortcuts.onKeyDown(for: name) { handler(action) }
        }
        KeyboardShortcuts.onKeyDown(for: togglePause) { pause.toggle() }
    }

    /// Registration that failed earlier is dropped, so enabling again retries it
    /// without adding a second handler. While paused the shortcuts stay off.
    static func reregister() {
        guard !pause.isPaused else { return }
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

/// Pausing turns off every window shortcut but TogglePause, so the same key resumes.
/// Memory only: a relaunch always starts with shortcuts on, and the menu bar scene
/// observes it without writing to UserDefaults.
@MainActor @Observable
final class ShortcutPause {
    private(set) var isPaused = false

    func toggle() {
        isPaused.toggle()
        if isPaused {
            KeyboardShortcuts.disable(Array(Shortcuts.names.values))
        } else {
            Shortcuts.reregister()
        }
    }
}
