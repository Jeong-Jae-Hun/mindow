import CoreGraphics

/// Window math in Accessibility coordinates (top-left origin, y grows downward).
/// Convert NSScreen frames with `ScreenGeometry.flipped` before calling.
public enum WindowLayout {
    public struct Context: Sendable {
        public var window: CGRect
        public var screen: CGRect
        public var step: Int

        public init(window: CGRect, screen: CGRect, step: Int = 0) {
            self.window = window
            self.screen = screen
            self.step = step
        }
    }

    public static let cycleFractions: [CGFloat] = [1.0 / 2, 1.0 / 3, 2.0 / 3]

    /// Make Larger / Make Smaller change each side by this share of the screen.
    static let resizeShare: CGFloat = 0.05
    /// Make Smaller stops at this share of the screen so a window never vanishes.
    static let minimumShare: CGFloat = 0.2

    /// Returns nil for actions that need more than one screen or history
    /// (display moves, undo, redo).
    public static func frame(for action: WindowAction, in context: Context) -> CGRect? {
        let s = context.screen
        let f = cycleFractions[context.step % cycleFractions.count]
        let rect: CGRect? = switch action {
        case .moveToLeftHalf: CGRect(x: s.minX, y: s.minY, width: s.width * f, height: s.height)
        case .moveToRightHalf: CGRect(x: s.maxX - s.width * f, y: s.minY, width: s.width * f, height: s.height)
        case .moveToTopHalf: CGRect(x: s.minX, y: s.minY, width: s.width, height: s.height * f)
        case .moveToBottomHalf: CGRect(x: s.minX, y: s.maxY - s.height * f, width: s.width, height: s.height * f)
        case .moveToUpperLeft: CGRect(x: s.minX, y: s.minY, width: s.width * f, height: s.height / 2)
        case .moveToUpperRight: CGRect(x: s.maxX - s.width * f, y: s.minY, width: s.width * f, height: s.height / 2)
        case .moveToLowerLeft: CGRect(x: s.minX, y: s.midY, width: s.width * f, height: s.height / 2)
        case .moveToLowerRight: CGRect(x: s.maxX - s.width * f, y: s.midY, width: s.width * f, height: s.height / 2)
        case .moveToNextThird: third(after: context.window, in: s, offset: 1)
        case .moveToPreviousThird: third(after: context.window, in: s, offset: -1)
        case .moveToFullscreen: s
        case .moveToCenter: centered(context.window.size, in: s)
        case .makeLarger: resized(context.window, in: s, by: 1)
        case .makeSmaller: resized(context.window, in: s, by: -1)
        case .moveToNextDisplay, .moveToPreviousDisplay, .undoLastMove, .redoLastMove: nil
        }
        return rect.map(rounded)
    }

    /// Keeps the window's relative position and size when it moves between screens.
    public static func moveProportionally(_ window: CGRect, between screens: (from: CGRect, to: CGRect)) -> CGRect {
        let (from, to) = screens
        let sx = to.width / from.width
        let sy = to.height / from.height
        let moved = CGRect(
            x: to.minX + (window.minX - from.minX) * sx,
            y: to.minY + (window.minY - from.minY) * sy,
            width: window.width * sx,
            height: window.height * sy
        )
        return rounded(fitInside(moved, screen: to))
    }

    /// Shifts a frame back onto the screen without resizing it. A window larger
    /// than the screen (apps with a minimum size) is pinned to the top-left edge.
    public static func fitInside(_ frame: CGRect, screen: CGRect) -> CGRect {
        let x = min(max(frame.minX, screen.minX), max(screen.minX, screen.maxX - frame.width))
        let y = min(max(frame.minY, screen.minY), max(screen.minY, screen.maxY - frame.height))
        return CGRect(origin: CGPoint(x: x, y: y), size: frame.size)
    }

    /// Picks the screen that holds most of the window, or the first one when it is off-screen.
    public static func screenIndex(for window: CGRect, among screens: [CGRect]) -> Int? {
        let areas = screens.map { s -> CGFloat in
            let i = s.intersection(window)
            return i.isNull ? 0 : i.width * i.height
        }
        guard let best = areas.indices.max(by: { areas[$0] < areas[$1] }) else { return nil }
        return areas[best] > 0 ? best : 0
    }

    /// Apps round or clamp the frame they accept, so equality uses a small tolerance.
    public static func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
        let t: CGFloat = 2
        return abs(a.minX - b.minX) <= t && abs(a.minY - b.minY) <= t
            && abs(a.width - b.width) <= t && abs(a.height - b.height) <= t
    }

    // ─── Private ───

    /// Columns on a landscape screen, rows on a portrait one. A window that is
    /// not on a third starts at the first (next) or last (previous) cell.
    private static func third(after window: CGRect, in s: CGRect, offset: Int) -> CGRect {
        let landscape = s.width >= s.height
        let cells = (0..<3).map { i -> CGRect in
            landscape
                ? CGRect(x: s.minX + s.width * CGFloat(i) / 3, y: s.minY, width: s.width / 3, height: s.height)
                : CGRect(x: s.minX, y: s.minY + s.height * CGFloat(i) / 3, width: s.width, height: s.height / 3)
        }
        guard let current = cells.firstIndex(where: { isClose(rounded($0), window) }) else {
            return offset > 0 ? cells[0] : cells[2]
        }
        return cells[(current + offset + 3) % 3]
    }

    private static func centered(_ size: CGSize, in s: CGRect) -> CGRect {
        let w = min(size.width, s.width)
        let h = min(size.height, s.height)
        return CGRect(x: s.midX - w / 2, y: s.midY - h / 2, width: w, height: h)
    }

    private static func resized(_ window: CGRect, in s: CGRect, by direction: CGFloat) -> CGRect {
        let dx = s.width * resizeShare * direction
        let dy = s.height * resizeShare * direction
        let w = min(s.width, max(s.width * minimumShare, window.width + dx * 2))
        let h = min(s.height, max(s.height * minimumShare, window.height + dy * 2))
        let grown = CGRect(x: window.midX - w / 2, y: window.midY - h / 2, width: w, height: h)
        return fitInside(grown, screen: s)
    }

    private static func rounded(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX.rounded(), y: r.minY.rounded(), width: r.width.rounded(), height: r.height.rounded())
    }
}
