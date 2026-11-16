/// Raw values are Spectacle's `shortcut_name`s, so importing a Spectacle
/// `Shortcuts.json` maps names one to one and stored shortcuts keep the same keys.
/// Actions Spectacle lacks use names it never had, so an import cannot touch them.
public enum WindowAction: String, CaseIterable, Sendable {
    case moveToLeftHalf = "MoveToLeftHalf"
    case moveToRightHalf = "MoveToRightHalf"
    case moveToTopHalf = "MoveToTopHalf"
    case moveToBottomHalf = "MoveToBottomHalf"
    case moveToUpperLeft = "MoveToUpperLeft"
    case moveToUpperRight = "MoveToUpperRight"
    case moveToLowerLeft = "MoveToLowerLeft"
    case moveToLowerRight = "MoveToLowerRight"
    case moveToNextThird = "MoveToNextThird"
    case moveToPreviousThird = "MoveToPreviousThird"
    case moveToNextFourth = "MoveToNextFourth"
    case moveToPreviousFourth = "MoveToPreviousFourth"
    case moveToNextRowThird = "MoveToNextRowThird"
    case moveToPreviousRowThird = "MoveToPreviousRowThird"
    case moveToCenterTwoThirds = "MoveToCenterTwoThirds"
    case moveToFirstTwoThirds = "MoveToFirstTwoThirds"
    case moveToLastTwoThirds = "MoveToLastTwoThirds"
    case moveToFullscreen = "MoveToFullscreen"
    case maximizeHeight = "MaximizeHeight"
    case moveToCenter = "MoveToCenter"
    case moveToNextDisplay = "MoveToNextDisplay"
    case moveToPreviousDisplay = "MoveToPreviousDisplay"
    case makeLarger = "MakeLarger"
    case makeSmaller = "MakeSmaller"
    case undoLastMove = "UndoLastMove"
    case redoLastMove = "RedoLastMove"

    public var title: String {
        switch self {
        case .moveToLeftHalf: "Left Half"
        case .moveToRightHalf: "Right Half"
        case .moveToTopHalf: "Top Half"
        case .moveToBottomHalf: "Bottom Half"
        case .moveToUpperLeft: "Upper Left"
        case .moveToUpperRight: "Upper Right"
        case .moveToLowerLeft: "Lower Left"
        case .moveToLowerRight: "Lower Right"
        case .moveToNextThird: "Next Third"
        case .moveToPreviousThird: "Previous Third"
        case .moveToNextFourth: "Next Fourth"
        case .moveToPreviousFourth: "Previous Fourth"
        case .moveToNextRowThird: "Next Row Third"
        case .moveToPreviousRowThird: "Previous Row Third"
        case .moveToCenterTwoThirds: "Center Two Thirds"
        case .moveToFirstTwoThirds: "First Two Thirds"
        case .moveToLastTwoThirds: "Last Two Thirds"
        case .moveToFullscreen: "Fullscreen"
        case .maximizeHeight: "Maximize Height"
        case .moveToCenter: "Center"
        case .moveToNextDisplay: "Next Display"
        case .moveToPreviousDisplay: "Previous Display"
        case .makeLarger: "Make Larger"
        case .makeSmaller: "Make Smaller"
        case .undoLastMove: "Undo Last Move"
        case .redoLastMove: "Redo Last Move"
        }
    }

    /// Grids whose cells Next/Previous actions walk. Next and Previous of one grid share
    /// the cell index; different grids have different cells, so they never share it.
    public enum CellGrid: Sendable {
        /// Columns on a landscape screen, rows on a portrait one.
        case thirds, fourths
        /// Rows whatever the screen's orientation.
        case rowThirds
    }

    /// Whether a press can continue the cycle `previous` left: the same half or corner
    /// steps through `WindowLayout.cycleFractions`, and Next/Previous of one grid walk its cells.
    public func continues(_ previous: WindowAction) -> Bool {
        if let cellGrid { return previous.cellGrid == cellGrid }
        return cyclesOnRepeat && self == previous
    }

    public var cellGrid: CellGrid? {
        switch self {
        case .moveToNextThird, .moveToPreviousThird: .thirds
        case .moveToNextFourth, .moveToPreviousFourth: .fourths
        case .moveToNextRowThird, .moveToPreviousRowThird: .rowThirds
        default: nil
        }
    }

    /// Pressing the same shortcut again steps through `WindowLayout.cycleFractions`.
    public var cyclesOnRepeat: Bool {
        switch self {
        case .moveToLeftHalf, .moveToRightHalf, .moveToTopHalf, .moveToBottomHalf,
             .moveToUpperLeft, .moveToUpperRight, .moveToLowerLeft, .moveToLowerRight:
            true
        default:
            false
        }
    }
}
