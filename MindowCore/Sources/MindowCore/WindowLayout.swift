import CoreGraphics

/// Window math in Accessibility coordinates (top-left origin, y grows downward).
/// Convert NSScreen frames with `ScreenGeometry.flipped` before calling.
public enum WindowLayout {
    public struct Context: Sendable {
        public var window: CGRect
        public var screen: CGRect
        /// Step of the same cycle the last press used, from `RepeatCycle`. Nil starts over.
        public var previousStep: Int?
        /// Space around tiled placements: this much from the screen edges and between
        /// neighbouring tiles. Center, Make Larger and Make Smaller ignore it.
        public var gap: CGFloat

        public init(window: CGRect, screen: CGRect, previousStep: Int?, gap: CGFloat = 0) {
            self.window = window
            self.screen = screen
            self.previousStep = previousStep
            self.gap = gap
        }
    }

    /// Where to put the window, and which cycle step that is (a fraction index for
    /// halves and corners, a cell index for thirds and fourths, 0 otherwise).
    public struct Placement: Equatable, Sendable {
        public var frame: CGRect
        public var step: Int

        public init(frame: CGRect, step: Int) {
            self.frame = frame
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
    public static func placement(for action: WindowAction, in context: Context) -> Placement? {
        let s = context.screen
        let step = context.previousStep.map { ($0 + 1) % cycleFractions.count } ?? 0
        let f = cycleFractions[step]
        let rect: CGRect? = switch action {
        case .moveToLeftHalf: CGRect(x: s.minX, y: s.minY, width: s.width * f, height: s.height)
        case .moveToRightHalf: CGRect(x: s.maxX - s.width * f, y: s.minY, width: s.width * f, height: s.height)
        case .moveToTopHalf: CGRect(x: s.minX, y: s.minY, width: s.width, height: s.height * f)
        case .moveToBottomHalf: CGRect(x: s.minX, y: s.maxY - s.height * f, width: s.width, height: s.height * f)
        case .moveToUpperLeft: CGRect(x: s.minX, y: s.minY, width: s.width * f, height: s.height / 2)
        case .moveToUpperRight: CGRect(x: s.maxX - s.width * f, y: s.minY, width: s.width * f, height: s.height / 2)
        case .moveToLowerLeft: CGRect(x: s.minX, y: s.midY, width: s.width * f, height: s.height / 2)
        case .moveToLowerRight: CGRect(x: s.maxX - s.width * f, y: s.midY, width: s.width * f, height: s.height / 2)
        case .moveToNextThird, .moveToPreviousThird, .moveToNextFourth, .moveToPreviousFourth,
             .moveToNextRowThird, .moveToPreviousRowThird: nil
        case .moveToCenterTwoThirds: CGRect(x: s.minX + s.width / 6, y: s.minY, width: s.width * 2 / 3, height: s.height)
        case .moveToFirstTwoThirds:
            s.width >= s.height
                ? CGRect(x: s.minX, y: s.minY, width: s.width * 2 / 3, height: s.height)
                : CGRect(x: s.minX, y: s.minY, width: s.width, height: s.height * 2 / 3)
        case .moveToLastTwoThirds:
            s.width >= s.height
                ? CGRect(x: s.maxX - s.width * 2 / 3, y: s.minY, width: s.width * 2 / 3, height: s.height)
                : CGRect(x: s.minX, y: s.maxY - s.height * 2 / 3, width: s.width, height: s.height * 2 / 3)
        case .moveToFullscreen: s
        case .maximizeHeight:
            CGRect(x: context.window.minX, y: s.minY + context.gap, width: context.window.width, height: s.height - context.gap * 2)
        case .moveToCenter:
            CGRect(
                x: s.midX - min(context.window.width, s.width) / 2,
                y: s.midY - min(context.window.height, s.height) / 2,
                width: min(context.window.width, s.width),
                height: min(context.window.height, s.height)
            )
        case .makeLarger: resized(context, by: 1)
        case .makeSmaller: resized(context, by: -1)
        case .moveToNextDisplay, .moveToPreviousDisplay, .undoLastMove, .redoLastMove: nil
        }
        if let rect {
            // Maximize Height applied the gap above to its height only; its x and width stay the window's.
            let framed = switch action {
            case .moveToCenter, .makeLarger, .makeSmaller, .maximizeHeight: rect
            default: tiled(rect, context)
            }
            return Placement(frame: rounded(framed), step: action.cyclesOnRepeat ? step : 0)
        }
        let landscape = s.width >= s.height
        switch action {
        case .moveToNextThird: return cell(context, (count: 3, rows: !landscape, offset: 1))
        case .moveToPreviousThird: return cell(context, (count: 3, rows: !landscape, offset: -1))
        case .moveToNextFourth: return cell(context, (count: 4, rows: !landscape, offset: 1))
        case .moveToPreviousFourth: return cell(context, (count: 4, rows: !landscape, offset: -1))
        case .moveToNextRowThird: return cell(context, (count: 3, rows: true, offset: 1))
        case .moveToPreviousRowThird: return cell(context, (count: 3, rows: true, offset: -1))
        default: return nil
        }
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
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    static let tolerance: CGFloat = 2

    // ─── Private ───

    /// Splits the screen into `count` columns, or rows when `rows` is set. A repeated
    /// press continues from the remembered cell, because an app with a large minimum
    /// size can land on the same frame for two cells. Otherwise a window spanning the
    /// full cross axis sits in the cell it overlaps most, and any other window starts
    /// at the first (next) or last (previous) cell.
    private static func cell(_ context: Context, _ walk: (count: Int, rows: Bool, offset: Int)) -> Placement {
        let (window, s) = (context.window, context.screen)
        let (count, rows, offset) = walk
        let n = CGFloat(count)
        let cells = (0..<count).map { i -> CGRect in
            let cell = rows
                ? CGRect(x: s.minX, y: s.minY + s.height * CGFloat(i) / n, width: s.width, height: s.height / n)
                : CGRect(x: s.minX + s.width * CGFloat(i) / n, y: s.minY, width: s.width / n, height: s.height)
            return tiled(cell, context)
        }
        // Every cell has the same cross-axis extent: the screen less the gap.
        let span = cells[0]
        let spansCrossAxis = rows
            ? abs(window.minX - span.minX) <= tolerance && abs(window.width - span.width) <= tolerance
            : abs(window.minY - span.minY) <= tolerance && abs(window.height - span.height) <= tolerance
        let overlaps = cells.map { cell -> CGFloat in
            let i = cell.intersection(window)
            return i.isNull ? 0 : i.width * i.height
        }
        let overlapped = overlaps.indices.max { overlaps[$0] < overlaps[$1] }.flatMap { overlaps[$0] > 0 ? $0 : nil }
        let index = if let current = context.previousStep ?? (spansCrossAxis ? overlapped : nil) {
            (current + offset + count) % count
        } else {
            offset > 0 ? 0 : count - 1
        }
        return Placement(frame: rounded(cells[index]), step: index)
    }

    /// Insets a tile by the full gap on edges that touch the screen and by half of it
    /// on edges shared with a neighbour, so two neighbours end up exactly `gap` apart.
    /// Edges are rounded, not origin and size, or a shared edge at a fraction (thirds
    /// of 1366) leaves a gap one point off. Half-up rounding shifts with whole points,
    /// so both sides of an edge round the same way. Gap 0 keeps the old frames as is.
    private static func tiled(_ r: CGRect, _ context: Context) -> CGRect {
        // Frames land on whole points, so a gap under one point would round away.
        let (s, gap) = (context.screen, context.gap.rounded())
        guard gap > 0 else { return r }
        let left = abs(r.minX - s.minX) <= tolerance ? gap : gap / 2
        let right = abs(r.maxX - s.maxX) <= tolerance ? gap : gap / 2
        let top = abs(r.minY - s.minY) <= tolerance ? gap : gap / 2
        let bottom = abs(r.maxY - s.maxY) <= tolerance ? gap : gap / 2
        let minX = (r.minX + left + 0.5).rounded(.down)
        let maxX = (r.maxX - right + 0.5).rounded(.down)
        let minY = (r.minY + top + 0.5).rounded(.down)
        let maxY = (r.maxY - bottom + 0.5).rounded(.down)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func resized(_ context: Context, by direction: CGFloat) -> CGRect {
        let (window, s) = (context.window, context.screen)
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
