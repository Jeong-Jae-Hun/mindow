import AppKit
import ApplicationServices
import MindowCore

// ─── Accessibility ───

private let positionAttribute = AXAttribute<CGPoint>(name: kAXPositionAttribute, type: .cgPoint)
private let sizeAttribute = AXAttribute<CGSize>(name: kAXSizeAttribute, type: .cgSize)
/// A window in its own macOS Space; it can't be moved or resized.
private let fullScreenAttribute = "AXFullScreen"

private struct AXAttribute<Value: BitwiseCopyable> {
    let name: String
    let type: AXValueType
}

/// Compares frames instead of AX error codes: a write can half succeed, and only
/// a real change belongs in the history.
private func didMove(_ applied: CGRect?, from current: CGRect) -> Bool {
    applied.map { !WindowLayout.isClose($0, current) } ?? false
}

// ─── Window manager ───

/// Moves the focused window through the Accessibility API. All geometry is in
/// AX coordinates; `MindowCore` does the math.
@MainActor
final class WindowManager {
    private var cycle = RepeatCycle()
    private var cycleWindow: AXUIElement?
    private var history = MoveHistory<AXUIElement>()
    private var maximized = MaximizeMemory<AXUIElement>()
    private let hud = ActionHUD()
    /// The frontmost app when the last menu opened. A menu bar click acts on it, not on
    /// whatever is frontmost when the item fires, in case opening the menu changed that.
    private(set) var menuTarget: NSRunningApplication?

    init() {
        // Menus post this on the main thread before tracking starts; a queue would deliver it late.
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil
        ) { [weak self] _ in
            guard Thread.isMainThread else { return }
            MainActor.assumeIsolated { self?.menuTarget = NSWorkspace.shared.frontmostApplication }
        }
    }

    /// Shortcuts act on the frontmost app; the menu passes `menuTarget`.
    func perform(_ action: WindowAction, in target: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) {
        guard AXIsProcessTrusted(),
              let app = target,
              let window = AXUIElementCreateApplication(app.processIdentifier).focusedWindow
        else {
            NSSound.beep()
            return
        }
        let screens = NSScreen.axFrames.map(\.visible)
        guard let current = window.frame, let index = WindowLayout.screenIndex(for: current, among: screens) else { return }

        let screen = screens[index]

        // A cycle continues only on the same window with nothing else in between.
        if cycleWindow != window || !(action.cyclesOnRepeat || action.cellGrid != nil) {
            cycle = RepeatCycle()
        }
        cycleWindow = window

        switch action {
        case .undoLastMove, .redoLastMove:
            let undoing = action == .undoLastMove
            let target = undoing ? history.undo(for: window, current: current) : history.redo(for: window, current: current)
            // The saved frame may be on another display, so fit it to its own screen.
            guard let target, let targetIndex = WindowLayout.screenIndex(for: target, among: screens) else { return }
            let applied = window.setFrame(target, within: screens[targetIndex])
            let reached = applied.map { WindowLayout.isClose($0, target) } ?? false
            let moved = didMove(applied, from: current)
            // Keep the step when the window got there, even if it was already there
            // (moved by hand). Otherwise the opposite call puts both stacks back.
            if !reached, !moved {
                _ = undoing ? history.redo(for: window, current: target) : history.undo(for: window, current: target)
            }
            if moved {
                hud.show(ActionLabel.text(for: action, step: 0), on: screens[targetIndex])
            }
        case .moveToNextDisplay, .moveToPreviousDisplay:
            guard screens.count > 1 else { return }
            let offset = action == .moveToNextDisplay ? 1 : -1
            let to = screens[(index + offset + screens.count) % screens.count]
            if didMove(window.setFrame(WindowLayout.moveProportionally(current, between: (screen, to)), within: to), from: current) {
                history.record(current, for: window)
                hud.show(ActionLabel.text(for: action, step: 0), on: to)
            }
        case .splitWithPrevious:
            // Nothing moves unless both windows can: a lone half is not what was asked
            // for. The other app may be hung, so its messages wait `messagingTimeout` at
            // most, and it moves first so a stalled write leaves this window alone.
            guard let previousApp = Shortcuts.frontmost.previous(before: app) else {
                NSSound.beep()
                return
            }
            let otherApp = AXUIElementCreateApplication(previousApp.processIdentifier)
            AXUIElementSetMessagingTimeout(otherApp, AXUIElement.messagingTimeout)
            guard let other = otherApp.focusedWindow else {
                NSSound.beep()
                return
            }
            AXUIElementSetMessagingTimeout(other, AXUIElement.messagingTimeout)
            // Each read that fails ends it, so a hung app costs one more timeout, not three.
            guard other.flag(kAXMinimizedAttribute) == false, other.flag(fullScreenAttribute) == false,
                  let otherCurrent = other.frame,
                  let frames = SplitWithPrevious.frames(of: (current, otherCurrent), on: (screen, Preferences.gapValue))
            else {
                NSSound.beep()
                return
            }
            guard let otherApplied = other.setFrame(frames.previous, within: screen) else { return }
            let otherMoved = didMove(otherApplied, from: otherCurrent)
            if otherMoved {
                history.record(otherCurrent, for: other)
            }
            let applied = window.setFrame(frames.current, within: screen)
            let moved = didMove(applied, from: current)
            if moved {
                history.record(current, for: window)
            }
            // A window that didn't answer leaves a half-done split: no label for that.
            if applied != nil, otherMoved || moved {
                hud.show(ActionLabel.text(for: action, step: 0), on: screen)
            }
        default:
            // The toggle covers size cycling; thirds and fourths always walk their cells.
            let remembered = action.cellGrid != nil || UserDefaults.standard.bool(forKey: Preferences.cycleOnRepeat)
            let previous = remembered ? cycle.previousStep(for: action, current: current) : nil
            let gap = Preferences.gapValue
            let context = WindowLayout.Context(window: current, screen: screen, previousStep: previous, gap: gap)
            guard let target = WindowLayout.placement(for: action, in: context) else { return }
            // Fullscreen again on a window Mindow maximized goes back to the frame it had.
            // Like undo, that frame may be on another display, so fit it to its own screen.
            let restored = action == .moveToFullscreen
                ? maximized.restoreFrame(for: window, at: (current, target.frame))
                : nil
            let destination = restored.flatMap { WindowLayout.screenIndex(for: $0, among: screens) }.map { screens[$0] } ?? screen
            guard let applied = window.setFrame(restored ?? target.frame, within: destination) else { return }
            if didMove(applied, from: current) {
                history.record(current, for: window)
                if restored != nil {
                    maximized.forget(window)
                } else if action == .moveToFullscreen {
                    maximized.remember(current, for: window)
                }
                hud.show(ActionLabel.text(for: action, step: target.step), on: destination)
            }
            cycle.record(action, placement: .init(frame: applied, step: target.step))
        }
    }

    /// Places a window dropped by drag snap, found by its owner and its frame at the
    /// drop. It goes on the screen under the cursor (`target.screen` indexes
    /// `NSScreen.axFrames`), not the one holding most of the window. Like a first press
    /// of the shortcut: step 0, recorded for undo, and the next press continues the
    /// cycle. Fullscreen never restores the remembered frame here, because a window
    /// dragged along the top edge can drop where it already filled the screen.
    func snap(_ target: SnapZone.Target, window dropped: (pid: pid_t, frame: CGRect, byCommand: Bool)) {
        let screens = NSScreen.axFrames.map(\.visible)
        guard AXIsProcessTrusted(), screens.indices.contains(target.screen) else { return }

        // Find the dropped window among its app's windows by frame. Every message waits
        // at most `messagingTimeout`, and the search stops at the first one left
        // unanswered, so an app that hangs midway costs one more timeout, not one per window.
        let app = AXUIElementCreateApplication(dropped.pid)
        AXUIElementSetMessagingTimeout(app, AXUIElement.messagingTimeout)
        var all: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &all) == .success,
              let windows = all as? [AXUIElement]
        else { return }
        var matches: [AXUIElement] = []
        for window in windows {
            AXUIElementSetMessagingTimeout(window, AXUIElement.messagingTimeout)
            guard let frame = window.frame else { return }
            if WindowLayout.isClose(frame, dropped.frame) { matches.append(window) }
        }
        // Two windows of one app on the same frame: only the focused one can be told
        // apart, and only when it is the one dragged. Command drags a window without
        // focusing it, so then neither is touched.
        if matches.count > 1, !dropped.byCommand, let window = app.focusedWindow {
            matches = matches.contains(window) ? [window] : []
        }
        guard matches.count == 1, let window = matches.first, let current = window.frame else { return }
        let screen = screens[target.screen]
        let gap = Preferences.gapValue
        let context = WindowLayout.Context(window: current, screen: screen, previousStep: nil, gap: gap)
        guard let placement = WindowLayout.placement(for: target.action, in: context),
              let applied = window.setFrame(placement.frame, within: screen)
        else { return }
        if didMove(applied, from: current) {
            history.record(current, for: window)
            if target.action == .moveToFullscreen {
                maximized.remember(current, for: window)
            }
            hud.show(ActionLabel.text(for: target.action, step: placement.step), on: screen)
        }
        cycle = RepeatCycle()
        cycleWindow = window
        cycle.record(target.action, placement: .init(frame: applied, step: placement.step))
    }
}

// ─── Screens ───

extension NSScreen {
    /// Every screen's frame and visible frame (without menu bar and Dock) in AX
    /// coordinates, left to right so Next/Previous Display walk the physical arrangement.
    @MainActor static var axFrames: [(frame: CGRect, visible: CGRect)] {
        guard let primaryHeight = screens.first?.frame.height else { return [] }
        return screens
            .map { (ScreenGeometry.flipped($0.frame, primaryScreenHeight: primaryHeight),
                    ScreenGeometry.flipped($0.visibleFrame, primaryScreenHeight: primaryHeight)) }
            .sorted { ($0.visible.minX, $0.visible.minY) < ($1.visible.minX, $1.visible.minY) }
    }
}

private extension AXUIElement {
    /// Upper bound per AX message, so an app that stopped responding can't hold the
    /// main thread for the system's default six seconds.
    static let messagingTimeout: Float = 0.25

    /// The app element's focused window. Also answers for an app that isn't in front.
    var focusedWindow: AXUIElement? {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(focused, to: AXUIElement.self)
    }

    /// See `AXFlag.value` for which answers count as no and which as a failed read.
    func flag(_ name: String) -> Bool? {
        var raw: CFTypeRef?
        return AXFlag.value(AXUIElementCopyAttributeValue(self, name as CFString, &raw), raw)
    }

    var frame: CGRect? {
        guard let origin = value(positionAttribute), let size = value(sizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Sets size, position, then size again (the allowed size can change on another
    /// display) and reads the frame back. Apps with a minimum size may keep a larger
    /// one, so the result is shifted back on screen. Returns the frame the window
    /// actually has, or nil when it cannot be read.
    ///
    /// A write the app never answered (`.cannotComplete`, also what a messaging timeout
    /// gives) stops it: every further message would wait just as long on the main thread.
    func setFrame(_ target: CGRect, within screen: CGRect) -> CGRect? {
        guard set(sizeAttribute, to: target.size) != .cannotComplete,
              set(positionAttribute, to: target.origin) != .cannotComplete,
              set(sizeAttribute, to: target.size) != .cannotComplete,
              let applied = frame
        else { return nil }
        let fitted = WindowLayout.fitInside(applied, screen: screen)
        guard fitted.origin != applied.origin else { return applied }
        guard set(positionAttribute, to: fitted.origin) != .cannotComplete else { return nil }
        return frame
    }

    func value<Value>(_ attribute: AXAttribute<Value>) -> Value? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute.name as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }
        return withUnsafeTemporaryAllocation(of: Value.self, capacity: 1) { buffer in
            guard let base = buffer.baseAddress,
                  AXValueGetValue(unsafeDowncast(raw, to: AXValue.self), attribute.type, base)
            else { return nil }
            return base.pointee
        }
    }

    func set<Value>(_ attribute: AXAttribute<Value>, to value: Value) -> AXError {
        var value = value
        guard let axValue = AXValueCreate(attribute.type, &value) else { return .illegalArgument }
        return AXUIElementSetAttributeValue(self, attribute.name as CFString, axValue)
    }
}
