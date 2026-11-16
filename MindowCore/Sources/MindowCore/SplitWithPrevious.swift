import CoreGraphics

/// Split with Previous Window: the focused window and the focused window of the app
/// that was in front right before it share one screen, half each.
public enum SplitWithPrevious {
    /// The focused window takes the left half and the previous one the right half of
    /// `screen`, the same frames Left Half and Right Half give on a first press. When
    /// both already sit there, they trade sides, so pressing again swaps them and a
    /// third press puts them back. Any other arrangement starts from the left.
    public static func frames(
        of windows: (current: CGRect, previous: CGRect),
        on screen: (frame: CGRect, gap: CGFloat)
    ) -> (current: CGRect, previous: CGRect)? {
        let (current, previous) = windows
        let context = WindowLayout.Context(window: current, screen: screen.frame, previousStep: nil, gap: screen.gap)
        guard let left = WindowLayout.placement(for: .moveToLeftHalf, in: context)?.frame,
              let right = WindowLayout.placement(for: .moveToRightHalf, in: context)?.frame
        else { return nil }
        let placed = WindowLayout.isClose(current, left) && WindowLayout.isClose(previous, right)
        return placed ? (right, left) : (left, right)
    }
}

/// The last two apps activated. The caller leaves out Mindow itself, so opening its
/// menu or Settings doesn't count as a switch.
public struct RecentApps<App: Equatable> {
    public private(set) var last: App?
    private var beforeLast: App?

    public init() {}

    /// The same app again (back from Mindow) keeps the order as it was.
    public mutating func activated(_ app: App) {
        guard app != last else { return }
        beforeLast = last
        last = app
    }

    /// The app in front right before `target`. Usually `target` is `last`; when its
    /// activation hasn't arrived yet, `last` is the one before it. Never `target` itself.
    public func previous(before target: App) -> App? {
        let previous = target == last ? beforeLast : last
        return previous == target ? nil : previous
    }
}
