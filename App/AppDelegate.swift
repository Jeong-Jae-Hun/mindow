import AppKit
import MindowCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsWindowController()
    let windows = WindowManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            Preferences.showMenuBarIcon: true,
            Preferences.cycleOnRepeat: true,
        ])
        Shortcuts.register { [windows] action in windows.perform(action) }
        if !AXIsProcessTrusted() || SpectacleShortcuts.isSpectacleRunning {
            settings.show()
        }
        // Spectacle holds the same keys while it runs, so our registration fails.
        // Register again once it quits.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == SpectacleShortcuts.bundleIdentifier else { return }
            MainActor.assumeIsolated { Shortcuts.sync() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { Shortcuts.frontmost.update(app) }
        }
        // An excluded app can already be in front at launch; no activation follows.
        Shortcuts.frontmost.update(NSWorkspace.shared.frontmostApplication)
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
