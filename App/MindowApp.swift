import SwiftUI

@main
struct MindowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(Preferences.showMenuBarIcon) private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra("Mindow", systemImage: "rectangle.split.2x2", isInserted: $showMenuBarIcon) {
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
    static let importedFromSpectacleAt = "mindow.importedFromSpectacleAt"
}
