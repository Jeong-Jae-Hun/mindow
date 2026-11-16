import AppKit
import ApplicationServices
import MindowCore

// ─── Accessibility ───

let positionAttribute = AXAttribute<CGPoint>(name: kAXPositionAttribute, type: .cgPoint)
let sizeAttribute = AXAttribute<CGSize>(name: kAXSizeAttribute, type: .cgSize)
/// A window in its own macOS Space; it can't be moved or resized.
let fullScreenAttribute = "AXFullScreen"

struct AXAttribute<Value: BitwiseCopyable> {
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
    /// One instance for the app delegate and App Intents, which the system creates on its own.
    static let shared = WindowManager()
    private var cycle = RepeatCycle()
    private var cycleWindow: AXUIElement?
    /// Every change is a window Mindow moved (or an undo step), which `onMove` hears.
    private var history = MoveHistory<AXUIElement>() {
        didSet { onMove?() }
    }
    /// Display restore records frames again soon after Mindow moves a window.
    var onMove: (@MainActor () -> Void)?
    private var maximized = MaximizeMemory<AXUIElement>()
    /// Windows `autoPlace` is waiting on or moving.
    private var autoPlacing: Set<AXUIElement> = []
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

    /// URLs and the Shortcuts app act on the app in front. Opening a URL can bring
    /// Mindow itself forward, and it has no window to move, so then the app before it.
    /// Like the menu, this ignores pause: pausing only turns the keys off.
    func performOnFrontmost(_ action: WindowAction) {
        let front = NSWorkspace.shared.frontmostApplication
        perform(action, in: front == NSRunningApplication.current ? Shortcuts.frontmost.lastOther : front)
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

    /// Places a window an app just opened by the app's rule (`AutoPlacement`), like a
    /// first press: recorded for undo, so Undo puts it where the app opened it, but no
    /// label, since nobody pressed anything. Only standard windows that aren't minimized
    /// or full screen; sheets, dialogs and panels have other subroles.
    ///
    /// New windows often size or place themselves right after they appear, which would
    /// undo a move made at once, so it waits `autoPlaceDelay` first. An app that still
    /// moves the window afterwards gets one more try at the same target: worked out
    /// again from the moved frame, Make Larger would grow it twice. Undo keeps the frame
    /// from before the first move that happened, whichever pass made it.
    func autoPlace(_ window: AXUIElement, of bundleID: String) async {
        // A window that opened as the observer was added is both created and listed;
        // placing it twice would grow it twice under Make Larger.
        guard autoPlacing.insert(window).inserted else { return }
        defer { autoPlacing.remove(window) }
        AXUIElementSetMessagingTimeout(window, AXUIElement.messagingTimeout)
        var first: (rule: AppRule, frame: CGRect, screen: CGRect, applied: CGRect)?
        var recorded = false
        for delay in [Self.autoPlaceDelay, Self.autoPlaceDelay * 2] {
            try? await Task.sleep(for: delay)
            // Read again after every wait, so a rule removed or an app excluded meanwhile
            // wins. Each read that fails ends it: a hung app costs one timeout, not four.
            guard AXIsProcessTrusted(), !ExcludedApps.stored.contains(bundleID),
                  let rule = AppRules.stored.rule(for: bundleID),
                  window.string(kAXSubroleAttribute) == kAXStandardWindowSubrole,
                  window.flag(kAXMinimizedAttribute) == false, window.flag(fullScreenAttribute) == false,
                  let current = window.frame
            else { return }
            let target: (frame: CGRect, screen: CGRect)
            if let first {
                // Only for a window the app moved off the first pass's frame, by the same rule.
                guard rule == first.rule, !WindowLayout.isClose(current, first.applied) else { return }
                target = (first.frame, first.screen)
            } else {
                let screens = NSScreen.axFrames.map(\.visible)
                guard let placement = rule.placement(for: current, among: screens, gap: Preferences.gapValue) else { return }
                target = (placement.frame, screens[placement.screen])
            }
            guard let applied = window.setFrame(target.frame, within: target.screen) else { return }
            if !recorded, didMove(applied, from: current) {
                recorded = true
                history.record(current, for: window)
                if rule.action == .moveToFullscreen {
                    maximized.remember(current, for: window)
                }
            }
            first = (rule, target.frame, target.screen, applied)
        }
    }

    private static let autoPlaceDelay: Duration = .seconds(0.15)
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

extension AXUIElement {
    /// Upper bound per AX message, so an app that stopped responding can't hold the
    /// main thread for the system's default six seconds.
    static let messagingTimeout: Float = 0.25

    /// The app element's windows, nil when it doesn't answer, so a caller that keeps
    /// what it read can tell an app without windows from one that is hung.
    var windows: [AXUIElement]? {
        var all: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, kAXWindowsAttribute as CFString, &all) == .success else { return nil }
        return all as? [AXUIElement] ?? []
    }

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

    /// Empty for an attribute the element doesn't have, nil when the read failed, as
    /// `AXFlag.value` tells them apart.
    func string(_ name: String) -> String? {
        var raw: CFTypeRef?
        switch AXUIElementCopyAttributeValue(self, name as CFString, &raw) {
        case .success: return raw as? String ?? ""
        case .attributeUnsupported, .noValue: return ""
        default: return nil
        }
    }

    var frame: CGRect? {
        guard let origin = value(positionAttribute), let size = value(sizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Sets size, position, then size again (the allowed size can change on another
    /// display) and reads the frame back. Apps with a minimum size may keep a larger
    /// one, so the result is shifted back on `screen`; nil leaves it where the app put
    /// it. Returns the frame the window actually has, or nil when it cannot be read.
    ///
    /// A write the app never answered (`.cannotComplete`, also what a messaging timeout
    /// gives) stops it: every further message would wait just as long on the main thread.
    func setFrame(_ target: CGRect, within screen: CGRect?) -> CGRect? {
        guard set(sizeAttribute, to: target.size) != .cannotComplete,
              set(positionAttribute, to: target.origin) != .cannotComplete,
              set(sizeAttribute, to: target.size) != .cannotComplete,
              let applied = frame
        else { return nil }
        guard let screen else { return applied }
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
