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

    var body: some Scene {
        MenuBarExtra("Mindow", systemImage: "rectangle.split.2x2", isInserted: menuBarIconInserted) {
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
    static let importedFromSpectacleAt = "mindow.importedFromSpectacleAt"
}
