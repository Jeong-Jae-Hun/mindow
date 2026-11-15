import AppKit
import ApplicationServices
import MindowCore

/// Moves the focused window through the Accessibility API. All geometry is in
/// AX coordinates; `MindowCore` does the math.
@MainActor
final class WindowManager {
    private var cycle = RepeatCycle()
    private var cycleWindow: AXUIElement?
    private var history = MoveHistory<AXUIElement>()

    func perform(_ action: WindowAction) {
        var focused: CFTypeRef?
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              AXUIElementCopyAttributeValue(
                  AXUIElementCreateApplication(app.processIdentifier),
                  kAXFocusedWindowAttribute as CFString,
                  &focused
              ) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else {
            NSSound.beep()
            return
        }
        let window = unsafeDowncast(focused, to: AXUIElement.self)
        guard let current = window.frame, let primaryHeight = NSScreen.screens.first?.frame.height else { return }

        // Visible frames (without menu bar and Dock), left to right so Next/Previous
        // Display walk the physical arrangement.
        let screens = NSScreen.screens
            .map { ScreenGeometry.flipped($0.visibleFrame, primaryScreenHeight: primaryHeight) }
            .sorted { ($0.minX, $0.minY) < ($1.minX, $1.minY) }
        guard let index = WindowLayout.screenIndex(for: current, among: screens) else { return }
        let screen = screens[index]

        // Cycling continues only on the same window with nothing else in between.
        if cycleWindow != window || !action.cyclesOnRepeat {
            cycle = RepeatCycle()
        }
        cycleWindow = window

        switch action {
        case .undoLastMove, .redoLastMove:
            let undoing = action == .undoLastMove
            let target = undoing ? history.undo(for: window, current: current) : history.redo(for: window, current: current)
            // The saved frame may be on another display, so fit it to its own screen.
            guard let target, let targetIndex = WindowLayout.screenIndex(for: target, among: screens) else { return }
            if window.setFrame(target, within: screens[targetIndex]) == nil {
                // The window did not move: the opposite call puts both stacks back as they were.
                _ = undoing ? history.redo(for: window, current: target) : history.undo(for: window, current: target)
            }
        case .moveToNextDisplay, .moveToPreviousDisplay:
            guard screens.count > 1 else { return }
            let offset = action == .moveToNextDisplay ? 1 : -1
            let to = screens[(index + offset + screens.count) % screens.count]
            if window.setFrame(WindowLayout.moveProportionally(current, between: (screen, to)), within: to) != nil {
                history.record(current, for: window)
            }
        default:
            let cycling = UserDefaults.standard.bool(forKey: Preferences.cycleOnRepeat)
            let step = cycling ? cycle.begin(action, current: current) : 0
            guard let target = WindowLayout.frame(for: action, in: .init(window: current, screen: screen, step: step)),
                  let applied = window.setFrame(target, within: screen)
            else { return }
            history.record(current, for: window)
            if cycling {
                cycle.finish(applied: applied)
            }
        }
    }
}

// ─── Accessibility ───

private struct AXAttribute<Value: BitwiseCopyable> {
    let name: String
    let type: AXValueType
}

private let positionAttribute = AXAttribute<CGPoint>(name: kAXPositionAttribute, type: .cgPoint)
private let sizeAttribute = AXAttribute<CGSize>(name: kAXSizeAttribute, type: .cgSize)

private extension AXUIElement {
    var frame: CGRect? {
        guard let origin = value(positionAttribute), let size = value(sizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Sets size, position, then size again (the allowed size can change on another
    /// display) and reads the frame back. Apps with a minimum size may keep a larger
    /// one, so the result is shifted back on screen. Returns nil when the app
    /// refused the move.
    func setFrame(_ target: CGRect, within screen: CGRect) -> CGRect? {
        set(sizeAttribute, to: target.size)
        guard set(positionAttribute, to: target.origin) else { return nil }
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
