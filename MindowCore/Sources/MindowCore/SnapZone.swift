import CoreGraphics

/// Where a window dragged to a screen edge goes. Points and frames are in
/// Accessibility coordinates, like `WindowLayout`.
public enum SnapZone {
    public struct Target: Equatable, Sendable {
        public var action: WindowAction
        /// Index into the screens passed to `target(at:screens:)`.
        public var screen: Int

        public init(action: WindowAction, screen: Int) {
            self.action = action
            self.screen = screen
        }
    }

    /// The cursor counts as on an edge within this distance of it.
    public static let edge: CGFloat = 6
    /// Side of the square at each corner that picks the corner over either edge.
    public static let corner: CGFloat = 20

    /// The action for a window dropped with the cursor at `point`, on the screen whose
    /// full frame (menu bar and Dock included, where the cursor can go) holds it.
    /// Left and right edges give halves, the top edge Fullscreen, corners the quarters.
    /// The bottom edge gives nothing: it sits under the Dock on most setups, and a
    /// window dragged down there is usually on its way to another screen or the Dock.
    ///
    /// Frames are half open, the way the cursor's pixel positions are: x runs from
    /// `minX` to `maxX - 1` on a 1x screen. So a point on the line two screens share
    /// belongs to the right (or lower) one, and both edges are `edge` pixels wide.
    public static func target(at point: CGPoint, screens: [CGRect]) -> Target? {
        guard let index = screens.firstIndex(where: { s in
            point.x >= s.minX && point.x < s.maxX && point.y >= s.minY && point.y < s.maxY
        }) else { return nil }
        let s = screens[index]
        let left = point.x < s.minX + edge
        let right = point.x >= s.maxX - edge
        let top = point.y < s.minY + edge
        let nearLeft = point.x < s.minX + corner
        let nearRight = point.x >= s.maxX - corner
        let nearTop = point.y < s.minY + corner
        let nearBottom = point.y >= s.maxY - corner
        // Corners first: their squares overlap both edges they touch.
        let action: WindowAction? = switch (nearLeft, nearRight, nearTop, nearBottom) {
        case (true, _, true, _): .moveToUpperLeft
        case (_, true, true, _): .moveToUpperRight
        case (true, _, _, true): .moveToLowerLeft
        case (_, true, _, true): .moveToLowerRight
        default: left ? .moveToLeftHalf : right ? .moveToRightHalf : top ? .moveToFullscreen : nil
        }
        return action.map { Target(action: $0, screen: index) }
    }
}
