import KeyboardShortcuts
import MindowCore
import SwiftUI

@main
struct MindowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(Preferences.showMenuBarIcon) private var showMenuBarIcon = true

    // Binding @AppStorage straight to isInserted hangs the app on macOS 26: the main
    // thread spins in scene updates and memory grows until it aborts. MenuBarExtra
    // writes the same value back, and each write updates the scene again. Only real
    // changes go through.
    private var menuBarIconInserted: Binding<Bool> {
        Binding(
            get: { showMenuBarIcon },
            set: { if $0 != showMenuBarIcon { showMenuBarIcon = $0 } }
        )
    }

    /// Same rule as `menuBarIconInserted`: the menu only toggles on a real change.
    private var pausedBinding: Binding<Bool> {
        Binding(
            get: { Shortcuts.pause.isPaused },
            set: { if $0 != Shortcuts.pause.isPaused { Shortcuts.pause.toggle() } }
        )
    }

    var body: some Scene {
        MenuBarExtra(
            "Mindow",
            systemImage: Shortcuts.pause.isPaused ? "rectangle.slash" : "rectangle.split.2x2",
            isInserted: menuBarIconInserted
        ) {
            ForEach(WindowAction.Family.allCases, id: \.self) { family in
                ForEach(family.actions, id: \.self) { action in
                    if let name = Shortcuts.names[action] {
                        Button(action.title) { appDelegate.windows.perform(action, in: appDelegate.windows.menuTarget) }
                            .globalKeyboardShortcut(name)
                    }
                }
                Divider()
            }
            Toggle(Shortcuts.togglePauseTitle, isOn: pausedBinding)
                .globalKeyboardShortcut(Shortcuts.togglePause)
            Divider()
            if let release = appDelegate.updates.available {
                Button("Update to v\(release.version.description)…") { NSWorkspace.shared.open(release.url) }
            }
            Button("Settings…") { appDelegate.settings.show() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit Mindow") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

enum Preferences {
    static let showMenuBarIcon = "mindow.showMenuBarIcon"
    static let cycleOnRepeat = "mindow.cycleOnRepeat"
    /// Points between tiled windows and around them; 0 (unset) keeps v0.1.1's frames.
    static let gap = "mindow.gap"
    static var gapValue: CGFloat { CGFloat(UserDefaults.standard.double(forKey: gap)) }
    static let importedFromSpectacleAt = "mindow.importedFromSpectacleAt"
    /// Bundle IDs; window action shortcuts are off while one of these apps is in front.
    static let excludedApps = "mindow.excludedApps"
    /// Dragging a window to a screen edge places it there.
    static let dragSnap = "mindow.dragSnap"
    /// A short label names each action that moved a window (`ActionHUD`).
    static let showHUD = "mindow.showHUD"
    /// Per Mac, like the menu bar icon: a settings export leaves both out.
    static let checkForUpdates = "mindow.checkForUpdates"
    static let lastUpdateCheck = "mindow.lastUpdateCheck"
}
