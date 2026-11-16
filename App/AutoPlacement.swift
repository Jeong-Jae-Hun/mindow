import AppKit
import ApplicationServices
import MindowCore

// ─── Auto placement ───

/// Places each new window of an app that has a rule (`AppRules`). One AXObserver per
/// running app with a rule, for its window-created notification, and only while Mindow
/// is trusted. The observers follow rule and exclusion edits, launches and quits.
/// Windows that already exist when a rule is added or Mindow starts stay where they are.
@MainActor
final class AutoPlacement {
    /// An app that just launched may not answer Accessibility yet; it is asked again
    /// this often, this many times.
    private static let retryDelay: Duration = .seconds(0.5)
    private static let attempts = 4

    private let windows: WindowManager
    private var observers: [pid_t: AXObserver] = [:]
    /// Apps the observers were last set up for (rules less exclusions, empty while not
    /// trusted), so the frequent defaults change notification costs nothing otherwise.
    private var watched: Set<String> = []

    init(windows: WindowManager) {
        self.windows = windows
        // Fires for every default anyone writes. `sync` writes none, so it can't loop.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        // AXIsProcessTrusted can still give the old answer when this arrives (see DragSnap).
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.sync()
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                guard let self, self.watched.contains(app.bundleIdentifier ?? "") else { return }
                Task { await self.watch(app, launched: true) }
            }
        }
        workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.unwatch(app.processIdentifier) }
        }
        sync()
    }

    /// Adds observers for running apps that gained a rule and drops those that lost
    /// theirs, were excluded, or all of them when trust is gone.
    func sync() {
        let excluded = ExcludedApps.stored
        let next: Set<String> = AXIsProcessTrusted()
            ? Set(AppRules.stored.rules.map(\.bundleID).filter { !excluded.contains($0) })
            : []
        guard next != watched else { return }
        watched = next
        let running = NSWorkspace.shared.runningApplications.filter {
            $0 != NSRunningApplication.current && next.contains($0.bundleIdentifier ?? "")
        }
        let keep = Set(running.map(\.processIdentifier))
        observers.keys.filter { !keep.contains($0) }.forEach(unwatch)
        for app in running where observers[app.processIdentifier] == nil {
            Task { await watch(app, launched: false) }
        }
    }

    /// For an app that just `launched`, its first windows may have opened before the
    /// observer was in place, so the windows it has then are placed too.
    private func watch(_ app: NSRunningApplication, launched: Bool) async {
        let pid = app.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, AXUIElement.messagingTimeout)
        for attempt in 0..<Self.attempts {
            if attempt > 0 {
                try? await Task.sleep(for: Self.retryDelay)
            }
            // Rules, exclusions or trust may have changed, or the app quit, while waiting.
            guard observers[pid] == nil, !app.isTerminated, watched.contains(app.bundleIdentifier ?? "") else { return }
            var created: AXObserver?
            guard AXObserverCreate(pid, { _, window, _, refcon in
                // Delivered on the main run loop, where the source is added below.
                guard let refcon else { return }
                let placement = Unmanaged<AutoPlacement>.fromOpaque(refcon).takeUnretainedValue()
                MainActor.assumeIsolated { placement.created(window) }
            }, &created) == .success, let observer = created else { return }
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            guard AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString, refcon) == .success else { continue }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observers[pid] = observer
            if launched, let bundleID = app.bundleIdentifier {
                for window in element.windows ?? [] {
                    Task { await windows.autoPlace(window, of: bundleID) }
                }
            }
            return
        }
    }

    private func unwatch(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    /// `autoPlace` reads the rule and the exclusion itself after waiting, so an edit
    /// since the observer was added wins, even before `sync` ran.
    private func created(_ window: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        else { return }
        Task { await windows.autoPlace(window, of: bundleID) }
    }
}

extension AppRules {
    @MainActor static var stored: AppRules {
        AppRules(plist: UserDefaults.standard.array(forKey: Preferences.appRules))
    }
}
