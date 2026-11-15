/// Raw values are Spectacle's `shortcut_name`s, so importing a Spectacle
/// `Shortcuts.json` maps names one to one and stored shortcuts keep the same keys.
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
    case moveToFullscreen = "MoveToFullscreen"
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
        case .moveToFullscreen: "Fullscreen"
        case .moveToCenter: "Center"
        case .moveToNextDisplay: "Next Display"
        case .moveToPreviousDisplay: "Previous Display"
        case .makeLarger: "Make Larger"
        case .makeSmaller: "Make Smaller"
        case .undoLastMove: "Undo Last Move"
        case .redoLastMove: "Redo Last Move"
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
