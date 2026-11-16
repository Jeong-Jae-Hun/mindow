import AppKit
import MindowCore

// ─── Action HUD ───

/// A short label in the middle of the screen a window just moved on, naming the
/// action and its cycle step (`ActionLabel`). One panel serves every action: a new one
/// while it shows replaces the text and starts the timer over.
@MainActor
final class ActionHUD {
    private static let visible: Duration = .seconds(0.6)
    private static let fade: TimeInterval = 0.2

    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private var hiding: Task<Void, Never>?

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
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        panel.contentView = background
    }

    /// `text` comes from `ActionLabel`. `screen` is the visible frame, in AX
    /// coordinates, of the screen the window is on.
    func show(_ text: String, on screen: CGRect) {
        guard UserDefaults.standard.bool(forKey: Preferences.showHUD),
              let primaryHeight = NSScreen.screens.first?.frame.height
        else { return }
        label.stringValue = text
        let fitting = label.fittingSize
        let size = CGSize(width: ceil(fitting.width) + 40, height: ceil(fitting.height) + 24)
        let center = ScreenGeometry.flipped(screen, primaryScreenHeight: primaryHeight)
        panel.setFrame(
            CGRect(x: (center.midX - size.width / 2).rounded(), y: (center.midY - size.height / 2).rounded(),
                   width: size.width, height: size.height),
            display: true
        )
        // A zero-length animation also stops a fade still running from the last action.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.orderFrontRegardless()
        hiding?.cancel()
        hiding = Task { [weak self] in
            try? await Task.sleep(for: Self.visible)
            guard let self, !Task.isCancelled else { return }
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                // Ends early when the next action's zero-length animation replaces it.
                await NSAnimationContext.runAnimationGroup { context in
                    context.duration = Self.fade
                    self.panel.animator().alphaValue = 0
                }
                guard !Task.isCancelled else { return }
            }
            panel.orderOut(nil)
        }
    }
}
