/// The text the action HUD shows after a window moved.
public enum ActionLabel {
    /// Names for `WindowLayout.cycleFractions`, in the same order: the share of the
    /// screen a half or corner takes at each step.
    static let fractionNames = ["1/2", "1/3", "2/3"]

    /// `step` is the placement's step (`WindowLayout.Placement.step`). Halves and
    /// corners add the share they take ("Left Half · 1/3"), thirds and fourths the
    /// cell they reached out of how many ("Next Third · 2/3"), the rest only the title.
    public static func text(for action: WindowAction, step: Int) -> String {
        if let grid = action.cellGrid {
            return "\(action.title) · \(step + 1)/\(grid.count)"
        }
        if action.cyclesOnRepeat, fractionNames.indices.contains(step) {
            return "\(action.title) · \(fractionNames[step])"
        }
        return action.title
    }
}
