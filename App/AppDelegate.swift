import AppKit
import MindowCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let windows = WindowManager.shared
    let updates = UpdateChecker()
    lazy var settings = SettingsWindowController(updates: updates)
    private var dragSnap: DragSnap?
    private var autoPlacement: AutoPlacement?
    private var displayRestore: DisplayRestore?

    /// A URL that launches Mindow arrives before `applicationDidFinishLaunching`, so the
    /// defaults its action reads are set here, and the app it means is read before
    /// Mindow may come to the front.
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            Preferences.showMenuBarIcon: true,
            Preferences.cycleOnRepeat: true,
            Preferences.dragSnap: true,
            Preferences.showHUD: true,
            Preferences.restoreOnDisplayChange: true,
            Preferences.checkForUpdates: true,
        ])
        Shortcuts.frontmost.update(NSWorkspace.shared.frontmostApplication)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Shortcuts.register { [windows] action in windows.perform(action) }
        // Registers the layout shortcuts; a layout URL at launch may already have.
        _ = LayoutLibrary.shared
        dragSnap = DragSnap(windows: windows)
        autoPlacement = AutoPlacement(windows: windows)
        displayRestore = DisplayRestore(windows: windows)
        updates.start()
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
        Shortcuts.sync()
    }

    /// `mindow://` URLs (`URLCommand`). Anything Mindow can't do, such as a layout
    /// name nobody saved, beeps and nothing else happens.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch URLCommand(url) {
            case .action(let action): windows.performOnFrontmost(action)
            case .layout(let name): Task { await LayoutLibrary.shared.restore(named: name) }
            case nil: NSSound.beep()
            }
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
