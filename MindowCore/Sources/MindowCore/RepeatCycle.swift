import CoreGraphics

/// Remembers the last placement so a repeated press can continue its cycle. It
/// continues only when the action allows it and the window has not moved since.
public struct RepeatCycle: Sendable {
    private var last: (action: WindowAction, frame: CGRect, step: Int)?

    public init() {}

    public func previousStep(for action: WindowAction, current: CGRect) -> Int? {
        guard let last, action.continues(last.action), WindowLayout.isClose(current, last.frame) else { return nil }
        return last.step
    }

    /// Pass the frame the window actually took, read back after moving it.
    public mutating func record(_ action: WindowAction, placement: WindowLayout.Placement) {
        last = (action, placement.frame, placement.step)
    }
}
