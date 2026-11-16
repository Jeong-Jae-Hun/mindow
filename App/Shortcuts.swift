import AppKit
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
    static let frontmost = FrontmostApp()

    static func register(_ handler: @escaping @MainActor (WindowAction) -> Void) {
        for (action, name) in names {
            KeyboardShortcuts.onKeyDown(for: name) { handler(action) }
        }
        KeyboardShortcuts.onKeyDown(for: togglePause) { pause.toggle() }
    }

    /// Turns the window action shortcuts on or off by `ExcludedApps.allowsActionShortcuts`;
    /// TogglePause is never touched. Registration that failed earlier is dropped, so
    /// enabling again retries it without adding a second handler.
    static func sync() {
        let actionNames = Array(names.values)
        if ExcludedApps.stored.allowsActionShortcuts(paused: pause.isPaused, frontmost: frontmost.bundleID) {
            KeyboardShortcuts.enable(actionNames)
        } else {
            KeyboardShortcuts.disable(actionNames)
        }
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
        Shortcuts.sync()
    }
}

/// Follows app activation so shortcuts turn off under an excluded app.
@MainActor @Observable
final class FrontmostApp {
    @ObservationIgnored private(set) var bundleID: String?
    /// Opening Settings brings Mindow to the front, so "Add Frontmost App" needs the
    /// app that was in front before it.
    private(set) var lastOther: NSRunningApplication?

    func update(_ app: NSRunningApplication?) {
        bundleID = app?.bundleIdentifier
        if let app, app != NSRunningApplication.current, app != lastOther {
            lastOther = app
        }
        Shortcuts.sync()
    }
}

extension ExcludedApps {
    @MainActor static var stored: ExcludedApps {
        ExcludedApps(UserDefaults.standard.stringArray(forKey: Preferences.excludedApps) ?? [])
    }
}
