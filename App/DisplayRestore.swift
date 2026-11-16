import AppKit
import ApplicationServices
import MindowCore

// ─── Display restore ───

/// Remembers where windows sit with each set of displays (`DisplayMemory`) and puts
/// them back when that set comes back, such as a monitor plugged in again. Memory only:
/// a relaunch starts empty.
///
/// Frames are read every `recordInterval` and shortly after each Mindow move. Reading
/// is on the main thread: the Accessibility API makes no promise about other threads.
/// Instead every message waits `messagingTimeout` at most, an app stops at its first
/// unanswered message, the main thread is let go between apps, and apps and windows
/// are capped, so one pass never holds it for long.
@MainActor
final class DisplayRestore {
    private static let recordInterval: Duration = .seconds(10)
    /// Displays send several changes while they come and go; restore once they stop.
    private static let settleDelay: Duration = .seconds(1.5)
    /// Mindow actions often come in runs (a cycle); one pass after the last of them.
    private static let afterMoveDelay: Duration = .seconds(1)

    private var memory = DisplayMemory<pid_t, AXUIElement>(current: .active)
    private var settling: Task<Void, Never>?
    private var pendingPass: Task<Void, Never>?
    private var recording = false

    init(windows: WindowManager) {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.displaysChanged() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.memory.forget(app.processIdentifier) }
        }
        windows.onMove = { [weak self] in self?.recordSoon() }
        Task { [weak self] in
            while !Task.isCancelled {
                await self?.record()
                try? await Task.sleep(for: Self.recordInterval)
            }
        }
    }

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Preferences.restoreOnDisplayChange) && AXIsProcessTrusted()
    }

    /// Recording stops at once; restoring waits until no change came for `settleDelay`.
    /// A change during a restore cancels it; the restore for the newer displays follows.
    private func displaysChanged() {
        memory.displaysChanged()
        settling?.cancel()
        settling = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            await self?.settle()
        }
    }

    /// Moves back only windows in the record for the new displays that the app still
    /// lists, to their exact recorded frames (one spanning two screens stays so), and
    /// leaves every other window alone. One app per main thread turn, like recording;
    /// recording waits until it is done.
    private func settle() async {
        let record = memory.settle(on: .active)
        for (pid, frames) in record.prefix(AXUIElement.passAppLimit) {
            await Task.yield()
            // Cancelled by a newer change, whose own settle resumes recording.
            guard !Task.isCancelled else { return }
            // Read after every yield: turning it off, losing trust or excluding an app
            // meanwhile stops it for the apps not reached yet.
            guard isEnabled else { break }
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
                  !ExcludedApps.stored.contains(app.bundleIdentifier)
            else { continue }
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, AXUIElement.messagingTimeout)
            // A window closed since it was recorded is no longer listed; it isn't asked.
            for window in (element.windows ?? []).filter({ frames[$0] != nil }).prefix(AXUIElement.passWindowLimit) {
                guard let frame = frames[window] else { continue }
                AXUIElementSetMessagingTimeout(window, AXUIElement.messagingTimeout)
                // The first unanswered message ends this app, so a hung app costs one timeout.
                guard let minimized = window.flag(kAXMinimizedAttribute),
                      let fullScreen = window.flag(fullScreenAttribute),
                      let current = window.frame
                else { break }
                guard !minimized, !fullScreen, !WindowLayout.isClose(current, frame) else { continue }
                guard window.setFrame(frame, within: nil) != nil else { break }
            }
        }
        memory.resume()
    }

    private func recordSoon() {
        pendingPass?.cancel()
        pendingPass = Task { [weak self] in
            try? await Task.sleep(for: Self.afterMoveDelay)
            guard !Task.isCancelled else { return }
            await self?.record()
        }
    }

    /// Reads the frames of every regular app's standard, not minimized, not full screen
    /// windows, one app per main thread turn. Each app's frames are recorded with the
    /// displays as they are right then, so a pass that a change interrupts records
    /// nothing for the old displays after it (`DisplayMemory.record`).
    private func record() async {
        guard isEnabled, !recording else { return }
        recording = true
        defer { recording = false }
        let excluded = ExcludedApps.stored
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0 != NSRunningApplication.current && !excluded.contains($0.bundleIdentifier)
        }
        for app in apps.prefix(AXUIElement.passAppLimit) {
            await Task.yield()
            guard isEnabled, !memory.isSettling, !app.isTerminated, !ExcludedApps.stored.contains(app.bundleIdentifier) else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, AXUIElement.messagingTimeout)
            // An app that stopped answering keeps what it had; a partial list would drop windows.
            guard let windows = element.standardWindows() else { continue }
            let frames = Dictionary(windows.map { ($0.element, $0.frame) }) { _, last in last }
            memory.record(frames, of: app.processIdentifier, in: .active)
        }
    }
}

extension DisplayConfiguration {
    /// The displays connected now. A display without a UUID (rare, virtual) counts by
    /// its ID, which is stable while it stays connected.
    @MainActor static var active: DisplayConfiguration {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return DisplayConfiguration([]) }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return DisplayConfiguration([]) }
        return DisplayConfiguration(ids.prefix(Int(count)).map { id in
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).flatMap { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String? }
            return Display(uuid: uuid ?? "id-\(id)", width: CGDisplayPixelsWide(id), height: CGDisplayPixelsHigh(id))
        })
    }
}
