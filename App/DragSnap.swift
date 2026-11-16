import AppKit
import MindowCore

// ─── Drag snap ───

/// Watches mouse drags system wide and places a window dropped with the cursor on a
/// screen edge (`SnapZone`), showing where it will go while the cursor is there.
///
/// Telling a window drag from a click, a resize or a text selection uses the window
/// server's window list, not AX: it costs no message to the app under the cursor, so a
/// hung app can't stall the main thread on every click. The window counts as dragged
/// once its origin moved and its size did not. AX is used once, on the drop.
@MainActor
final class DragSnap {
    private enum Gesture {
        case idle
        /// The button went down; the window is looked up on the first drag event only,
        /// so plain clicks cost nothing.
        case pressed
        case tracking(Drag)
        /// Not a window drag (no window, an excluded app, a resize); wait for mouse up.
        case ignored
    }

    private struct Drag {
        let window: WindowListEntry
        var lastRead: TimeInterval
        /// Screens as of the moment the window started moving; nil until then.
        var screens: [(frame: CGRect, visible: CGRect)]?
        var target: SnapZone.Target?
    }

    /// Window list reads while waiting for the window to move are at least this far apart.
    private static let readInterval: TimeInterval = 0.03

    private let windows: WindowManager
    private let preview = SnapPreview()
    private var monitors: [Any] = []
    private var gesture = Gesture.idle

    init(windows: WindowManager) {
        self.windows = windows
        // Fires for every default anyone writes. `update` only reads, so it can't loop.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        // Posted when any app's Accessibility permission changes. AXIsProcessTrusted can
        // still return the old answer right then, so ask again a moment later.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.update()
            }
        }
        update()
    }

    /// Installs the global mouse monitors only while the setting is on and Mindow is
    /// trusted, and removes them otherwise, so nothing runs per event when off.
    func update() {
        let wanted = UserDefaults.standard.bool(forKey: Preferences.dragSnap) && AXIsProcessTrusted()
        guard wanted == monitors.isEmpty else { return }
        if wanted {
            monitors = [
                NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                    MainActor.assumeIsolated { self?.mouseDown() }
                },
                NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
                    MainActor.assumeIsolated { self?.mouseDragged() }
                },
                NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                    MainActor.assumeIsolated { self?.mouseUp() }
                },
            ].compactMap { $0 }
        } else {
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
            gesture = .idle
            preview.hide()
        }
    }

    private func mouseDown() {
        gesture = .pressed
        preview.hide()
    }

    private func mouseDragged() {
        switch gesture {
        case .idle, .ignored:
            return
        case .pressed:
            guard let window = WindowListEntry.under(cursor),
                  window.pid != ProcessInfo.processInfo.processIdentifier,
                  !ExcludedApps.stored.contains(NSRunningApplication(processIdentifier: window.pid)?.bundleIdentifier)
            else {
                gesture = .ignored
                return
            }
            gesture = .tracking(Drag(window: window, lastRead: ProcessInfo.processInfo.systemUptime))
        case .tracking(var drag):
            if drag.screens == nil {
                let now = ProcessInfo.processInfo.systemUptime
                guard now - drag.lastRead >= Self.readInterval else { return }
                drag.lastRead = now
                switch Self.hasMoved(drag.window) {
                case nil:
                    gesture = .ignored
                    return
                case false?:
                    gesture = .tracking(drag)
                    return
                case true?:
                    // Moving from here on; the window list is not read again in this drag.
                    drag.screens = NSScreen.axFrames
                }
            }
            guard let screens = drag.screens else { return }
            let target = SnapZone.target(at: cursor, screens: screens.map(\.frame))
            if target != drag.target {
                drag.target = target
                // Always the first step of the action, like the drop: a fresh start, not a repeat.
                let frame = target.flatMap { target in
                    WindowLayout.placement(
                        for: target.action,
                        in: .init(window: drag.window.frame, screen: screens[target.screen].visible, previousStep: nil, gap: Preferences.gapValue)
                    )?.frame
                }
                if let frame { preview.show(frame) } else { preview.hide() }
            }
            gesture = .tracking(drag)
        }
    }

    private func mouseUp() {
        defer { gesture = .idle }
        preview.hide()
        guard case .tracking(let drag) = gesture else { return }
        // A short flick can end before a throttled read saw the window move.
        let screens = drag.screens ?? (Self.hasMoved(drag.window) == true ? NSScreen.axFrames : nil)
        guard let screens,
              let target = SnapZone.target(at: cursor, screens: screens.map(\.frame)),
              let frame = WindowListEntry.frame(of: drag.window.id)
        else { return }
        windows.snap(target, window: (drag.window.pid, frame))
    }

    /// Nil when the drag is not a window move (the window closed or changed size, and a
    /// resize can shift the origin too), false while it has not moved yet.
    private static func hasMoved(_ window: WindowListEntry) -> Bool? {
        guard let frame = WindowListEntry.frame(of: window.id), frame.size == window.frame.size else { return nil }
        return frame.origin != window.frame.origin
    }

    /// The cursor in AX coordinates.
    private var cursor: CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return ScreenGeometry.flipped(CGRect(origin: NSEvent.mouseLocation, size: .zero), primaryScreenHeight: primaryHeight).origin
    }
}

// ─── Window list ───

/// A window as the window server lists it. Its bounds are global, top-left origin
/// coordinates, the same space AX uses.
private struct WindowListEntry {
    let id: CGWindowID
    let pid: pid_t
    let frame: CGRect

    /// The frontmost normal-level window under `point`. Menus, panels and overlays sit
    /// on other levels and are skipped; dragging one of them does not snap.
    static func under(_ point: CGPoint) -> WindowListEntry? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        return list?.lazy.compactMap(WindowListEntry.init).first { $0.frame.contains(point) }
    }

    static func frame(of id: CGWindowID) -> CGRect? {
        let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]]
        return list?.first.flatMap(WindowListEntry.init)?.frame
    }

    /// Nil for anything but a visible window on the normal level.
    init?(_ info: [String: Any]) {
        guard (info[kCGWindowLayer as String] as? Int) == 0,
              (info[kCGWindowAlpha as String] as? Double ?? 0) > 0,
              let id = info[kCGWindowNumber as String] as? CGWindowID,
              let pid = info[kCGWindowOwnerPID as String] as? pid_t,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
        else { return nil }
        self.id = id
        self.pid = pid
        self.frame = frame
    }
}

// ─── Preview ───

/// A click-through, non-activating outline of where the dropped window will go.
@MainActor
private final class SnapPreview {
    private let panel: NSPanel

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // Mindow is never the active app, and panels hide on deactivation by default.
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.borderWidth = 2
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
        view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
        panel.contentView = view
    }

    /// `frame` is in AX coordinates.
    func show(_ frame: CGRect) {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        panel.setFrame(ScreenGeometry.flipped(frame, primaryScreenHeight: primaryHeight), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }
}
