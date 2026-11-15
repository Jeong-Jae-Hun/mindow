import CoreGraphics

/// Decides which `WindowLayout.cycleFractions` step a shortcut uses. The step
/// advances only when the same action repeats and the window has not moved since.
public struct RepeatCycle: Sendable {
    private var last: (action: WindowAction, frame: CGRect, step: Int)?
    private var pending: (action: WindowAction, step: Int)?

    public init() {}

    public mutating func begin(_ action: WindowAction, current: CGRect) -> Int {
        var step = 0
        if action.cyclesOnRepeat, let last, last.action == action, WindowLayout.isClose(current, last.frame) {
            step = (last.step + 1) % WindowLayout.cycleFractions.count
        }
        pending = (action, step)
        return step
    }

    /// Pass the frame the window actually took, read back after moving it.
    public mutating func finish(applied frame: CGRect) {
        guard let pending else { return }
        last = (pending.action, frame, pending.step)
        self.pending = nil
    }
}
