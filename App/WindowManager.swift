import AppKit
import ApplicationServices
import MindowCore

/// Moves the focused window through the Accessibility API. All geometry is in
/// AX coordinates; `MindowCore` does the math.
@MainActor
final class WindowManager {
    private var cycle = RepeatCycle()
    private var history = MoveHistory<AXUIElement>()

    func perform(_ action: WindowAction) {
        guard AXIsProcessTrusted(), let window = Self.focusedWindow(), let current = Self.frame(of: window) else {
            NSSound.beep()
            return
        }
        let screens = Self.visibleScreens()
        guard let index = WindowLayout.screenIndex(for: current, among: screens) else { return }
        let screen = screens[index]

        switch action {
        case .undoLastMove, .redoLastMove:
            let target = action == .undoLastMove
                ? history.undo(for: window, current: current)
                : history.redo(for: window, current: current)
            // The saved frame may be on another display, so fit it to its own screen.
            guard let target, let targetIndex = WindowLayout.screenIndex(for: target, among: screens) else { return }
            _ = Self.setFrame(target, of: window, within: screens[targetIndex])
            return
        case .moveToNextDisplay, .moveToPreviousDisplay:
            guard screens.count > 1 else { return }
            let offset = action == .moveToNextDisplay ? 1 : -1
            let to = screens[(index + offset + screens.count) % screens.count]
            history.record(current, for: window)
            _ = Self.setFrame(WindowLayout.moveProportionally(current, between: (screen, to)), of: window, within: to)
            return
        default:
            break
        }

        let cycling = UserDefaults.standard.bool(forKey: Preferences.cycleOnRepeat)
        let step = cycling ? cycle.begin(action, current: current) : 0
        guard let target = WindowLayout.frame(for: action, in: .init(window: current, screen: screen, step: step)) else { return }
        history.record(current, for: window)
        if let applied = Self.setFrame(target, of: window, within: screen), cycling {
            cycle.finish(applied: applied)
        }
    }

    // ─── Accessibility ───

    private static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var position = CGPoint.zero
        var size = CGSize.zero
        guard read(kAXPositionAttribute, of: window, type: .cgPoint, into: &position),
              read(kAXSizeAttribute, of: window, type: .cgSize, into: &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Sets size, then position, then reads the frame back. Apps with a minimum
    /// size may refuse the requested size, so the result is shifted back on screen.
    private static func setFrame(_ target: CGRect, of window: AXUIElement, within screen: CGRect) -> CGRect? {
        write(target.size, to: kAXSizeAttribute, of: window, type: .cgSize)
        write(target.origin, to: kAXPositionAttribute, of: window, type: .cgPoint)
        // Moving to another display can change the allowed size, so set it once more.
        write(target.size, to: kAXSizeAttribute, of: window, type: .cgSize)
        guard let applied = frame(of: window) else { return nil }
        let fitted = WindowLayout.fitInside(applied, screen: screen)
        guard fitted.origin != applied.origin else { return applied }
        write(fitted.origin, to: kAXPositionAttribute, of: window, type: .cgPoint)
        return frame(of: window)
    }

    private static func read<T: BitwiseCopyable>(_ attribute: String, of window: AXUIElement, type: AXValueType, into out: inout T) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return false }
        return AXValueGetValue(unsafeDowncast(value, to: AXValue.self), type, &out)
    }

    private static func write<T: BitwiseCopyable>(_ value: T, to attribute: String, of window: AXUIElement, type: AXValueType) {
        var value = value
        guard let axValue = AXValueCreate(type, &value) else { return }
        AXUIElementSetAttributeValue(window, attribute as CFString, axValue)
    }

    // ─── Screens ───

    /// Visible frames (without menu bar and Dock) in AX coordinates, ordered left to right
    /// so Next/Previous Display walk the physical arrangement.
    private static func visibleScreens() -> [CGRect] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        return NSScreen.screens
            .map { ScreenGeometry.flipped($0.visibleFrame, primaryScreenHeight: primaryHeight) }
            .sorted { ($0.minX, $0.minY) < ($1.minX, $1.minY) }
    }
}
