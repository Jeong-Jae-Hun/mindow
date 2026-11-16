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
    static let togglePauseTitle = "Pause Shortcuts"
    /// Every Mindow shortcut with its title, Pause first, then the actions in
    /// `allCases` order, then the layouts in theirs, which is the order a conflict
    /// warning lists the others in.
    static var titled: [(name: KeyboardShortcuts.Name, title: String)] {
        [(togglePause, togglePauseTitle)]
            + WindowAction.allCases.compactMap { action in names[action].map { ($0, action.title) } }
            + LayoutLibrary.shared.snapshots.layouts.compactMap { layout in layoutNames[layout.id].map { ($0, "Layout \(layout.name)") } }
    }
    /// The saved layouts' shortcut names by layout id, kept in step by `syncLayouts`.
    private(set) static var layoutNames: [String: KeyboardShortcuts.Name] = [:]
    static let pause = ShortcutPause()
    static let frontmost = FrontmostApp()

    static func register(_ handler: @escaping @MainActor (WindowAction) -> Void) {
        for (action, name) in names {
            KeyboardShortcuts.onKeyDown(for: name) { handler(action) }
        }
        KeyboardShortcuts.onKeyDown(for: togglePause) { pause.toggle() }
    }

    /// `Layout_<id>`, the UserDefaults key `KeyboardShortcuts_Layout_<id>`.
    static func layoutName(_ id: String) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("Layout_\(id)")
    }

    /// Adds a handler for each layout not seen yet, and drops the handler and the
    /// recorded shortcut of each layout gone, so a deleted layout's key is free again.
    /// Layout shortcuts then follow pause and exclusion like the action shortcuts.
    static func syncLayouts(_ ids: [String]) {
        for (id, name) in layoutNames where !ids.contains(id) {
            KeyboardShortcuts.removeHandler(for: name)
            KeyboardShortcuts.setShortcut(nil, for: name)
            layoutNames[id] = nil
        }
        for id in ids where layoutNames[id] == nil {
            let name = layoutName(id)
            KeyboardShortcuts.onKeyDown(for: name) { Task { await LayoutLibrary.shared.restore(id: id) } }
            layoutNames[id] = name
        }
        sync()
    }

    /// Turns the window action and layout shortcuts on or off by
    /// `ExcludedApps.allowsActionShortcuts`; TogglePause is never touched. Registration
    /// that failed earlier is dropped, so enabling again retries it without adding a
    /// second handler.
    static func sync() {
        let actionNames = Array(names.values) + Array(layoutNames.values)
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

    static func conflicts() -> [KeyboardShortcuts.Name: [String]] {
        let bindings = Dictionary(uniqueKeysWithValues: titled.map { entry in
            (entry.name, KeyboardShortcuts.getShortcut(for: entry.name).map {
                KeyBinding(carbonKeyCode: $0.carbonKeyCode, carbonModifiers: $0.carbonModifiers)
            })
        })
        return ShortcutConflicts.find(in: bindings).mapValues { others in
            titled.filter { others.contains($0.name) }.map(\.title)
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

/// Follows app activation so shortcuts turn off under an excluded app, and remembers
/// the app before the current one for Split with Previous Window.
@MainActor @Observable
final class FrontmostApp {
    @ObservationIgnored private(set) var bundleID: String?
    /// Apps other than Mindow. Opening Settings brings Mindow to the front, so "Add
    /// Frontmost App" needs the app that was in front before it.
    private var recent = RecentApps<NSRunningApplication>()

    var lastOther: NSRunningApplication? { recent.last }

    func update(_ app: NSRunningApplication?) {
        bundleID = app?.bundleIdentifier
        // Only a real change writes, so Settings doesn't redraw on every switch back.
        if let app, app != NSRunningApplication.current, app != recent.last {
            recent.activated(app)
        }
        Shortcuts.sync()
    }

    /// The app in front right before `target`, or nil when there is none or it quit.
    /// An excluded app still counts: the action is asked for explicitly, and exclusion
    /// only keeps Mindow's keys away from the app in front.
    func previous(before target: NSRunningApplication) -> NSRunningApplication? {
        recent.previous(before: target).flatMap { $0.isTerminated ? nil : $0 }
    }
}

extension ExcludedApps {
    @MainActor static var stored: ExcludedApps {
        ExcludedApps(UserDefaults.standard.stringArray(forKey: Preferences.excludedApps) ?? [])
    }
}
