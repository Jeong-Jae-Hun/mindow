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

        // A cycle continues only on the same window with nothing else in between.
        if cycleWindow != window || !(action.cyclesOnRepeat || action.isThird) {
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
            // The toggle covers size cycling; thirds always walk their cells.
            let remembered = action.isThird || UserDefaults.standard.bool(forKey: Preferences.cycleOnRepeat)
            let previous = remembered ? cycle.previousStep(for: action, current: current) : nil
            guard let target = WindowLayout.placement(for: action, in: .init(window: current, screen: screen, previousStep: previous)),
                  let applied = window.setFrame(target.frame, within: screen)
            else { return }
            if didMove(applied, from: current) {
                history.record(current, for: window)
            }
            cycle.record(action, placement: .init(frame: applied, step: target.step))
        }
    }
}

private extension AXUIElement {
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
