import AppKit
import MindowCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsWindowController()
    private let windows = WindowManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            Preferences.showMenuBarIcon: true,
            Preferences.cycleOnRepeat: true,
        ])
        Shortcuts.register { [windows] action in windows.perform(action) }
        if !AXIsProcessTrusted() || SpectacleShortcuts.isSpectacleRunning {
            settings.show()
        }
    }

    /// With the menu bar icon hidden, opening the app again is the only way back to settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }
}

extension SpectacleShortcuts {
    static var isSpectacleRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}
