import AppKit
import ApplicationServices
import MindowCore

// ─── Accessibility ───

private let positionAttribute = AXAttribute<CGPoint>(name: kAXPositionAttribute, type: .cgPoint)
private let sizeAttribute = AXAttribute<CGSize>(name: kAXSizeAttribute, type: .cgSize)

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
              let window = AXUIElementCreateApplication(app.processIdentifier).element(kAXFocusedWindowAttribute)
        else {
            NSSound.beep()
            return
        }
        let screens = NSScreen.axFrames.map(\.visible)
        guard let current = window.frame, let index = WindowLayout.screenIndex(for: current, among: screens) else { return }

        // A cycle continues only on the same window with nothing else in between.
        if cycleWindow != window || !(action.cyclesOnRepeat || action.cellGrid != nil) {
            cycle = RepeatCycle()
        }
        cycleWindow = window
        move(window, action, from: current, screen: index, among: screens)
    }

    /// Places a window dropped by drag snap, found by its owner and its frame at the
    /// drop. It goes on the screen under the cursor (`screen` indexes `NSScreen.axFrames`),
    /// not the one holding most of the window, and starts a fresh cycle as if its shortcut
    /// was pressed once, so the shortcut right after continues from there.
    func snap(_ action: WindowAction, pid: pid_t, frame: CGRect, screen: Int) {
        let screens = NSScreen.axFrames.map(\.visible)
        guard AXIsProcessTrusted(), screens.indices.contains(screen),
              let window = AXUIElement.window(of: pid, at: frame),
              let current = window.frame
        else { return }
        cycle = RepeatCycle()
        cycleWindow = window
        move(window, action, from: current, screen: screen, among: screens)
    }

    /// `screens` are visible frames; `screen` indexes the one the action is relative to.
    private func move(_ window: AXUIElement, _ action: WindowAction, from current: CGRect, screen index: Int, among screens: [CGRect]) {
        let screen = screens[index]
        switch action {
        case .undoLastMove, .redoLastMove:
            let undoing = action == .undoLastMove
            let target = undoing ? history.undo(for: window, current: current) : history.redo(for: window, current: current)
            // The saved frame may be on another display, so fit it to its own screen.
            guard let target, let targetIndex = WindowLayout.screenIndex(for: target, among: screens) else { return }
            let applied = window.setFrame(target, within: screens[targetIndex])
            let reached = applied.map { WindowLayout.isClose($0, target) } ?? false
            // Keep the step when the window got there, even if it was already there
            // (moved by hand). Otherwise the opposite call puts both stacks back.
            if !reached, !didMove(applied, from: current) {
                _ = undoing ? history.redo(for: window, current: target) : history.undo(for: window, current: target)
            }
        case .moveToNextDisplay, .moveToPreviousDisplay:
            guard screens.count > 1 else { return }
            let offset = action == .moveToNextDisplay ? 1 : -1
            let to = screens[(index + offset + screens.count) % screens.count]
            if didMove(window.setFrame(WindowLayout.moveProportionally(current, between: (screen, to)), within: to), from: current) {
                history.record(current, for: window)
            }
        default:
            // The toggle covers size cycling; thirds and fourths always walk their cells.
            let remembered = action.cellGrid != nil || UserDefaults.standard.bool(forKey: Preferences.cycleOnRepeat)
            let previous = remembered ? cycle.previousStep(for: action, current: current) : nil
            let gap = CGFloat(UserDefaults.standard.double(forKey: Preferences.gap))
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
            }
            cycle.record(action, placement: .init(frame: applied, step: target.step))
        }
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

    /// The window of `pid` whose frame is `frame`: the focused one when it matches
    /// (a dragged window usually is), otherwise the first match among all its windows.
    static func window(of pid: pid_t, at frame: CGRect) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        let focused = app.element(kAXFocusedWindowAttribute).map { [$0] } ?? []
        var all: CFTypeRef?
        let windows = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &all) == .success
            ? (all as? [AXUIElement]) ?? []
            : []
        return (focused + windows).first { window in
            AXUIElementSetMessagingTimeout(window, messagingTimeout)
            return window.frame.map { WindowLayout.isClose($0, frame) } ?? false
        }
    }

    func element(_ attribute: String) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(raw, to: AXUIElement.self)
    }

    var frame: CGRect? {
        guard let origin = value(positionAttribute), let size = value(sizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Sets size, position, then size again (the allowed size can change on another
    /// display) and reads the frame back. Apps with a minimum size may keep a larger
    /// one, so the result is shifted back on screen. Returns the frame the window
    /// actually has, or nil when it cannot be read.
    func setFrame(_ target: CGRect, within screen: CGRect) -> CGRect? {
        set(sizeAttribute, to: target.size)
        set(positionAttribute, to: target.origin)
        set(sizeAttribute, to: target.size)
        guard let applied = frame else { return nil }
        let fitted = WindowLayout.fitInside(applied, screen: screen)
        guard fitted.origin != applied.origin else { return applied }
        set(positionAttribute, to: fitted.origin)
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

    @discardableResult
    func set<Value>(_ attribute: AXAttribute<Value>, to value: Value) -> Bool {
        var value = value
        guard let axValue = AXValueCreate(attribute.type, &value) else { return false }
        return AXUIElementSetAttributeValue(self, attribute.name as CFString, axValue) == .success
    }
}
