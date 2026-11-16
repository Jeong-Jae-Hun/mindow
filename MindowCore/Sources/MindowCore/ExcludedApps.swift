/// Apps whose own shortcuts win: while one of them is frontmost, window action
/// shortcuts are off so the keys reach that app.
public struct ExcludedApps: Equatable, Sendable {
    public private(set) var bundleIDs: [String]

    /// Drops empty entries and repeats, keeping the first order, so a hand-edited
    /// default can't list an app twice.
    public init(_ bundleIDs: [String] = []) {
        var seen = Set<String>()
        self.bundleIDs = bundleIDs.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public func contains(_ bundleID: String?) -> Bool {
        bundleID.map(bundleIDs.contains) ?? false
    }

    /// False when nothing changed (empty or already listed), so the caller can skip the write.
    @discardableResult
    public mutating func add(_ bundleID: String) -> Bool {
        guard !bundleID.isEmpty, !contains(bundleID) else { return false }
        bundleIDs.append(bundleID)
        return true
    }

    public mutating func remove(_ bundleID: String) {
        bundleIDs.removeAll { $0 == bundleID }
    }

    /// The one rule for window action shortcuts. Pause, app switches and the
    /// re-registration after Spectacle quits all go through it, so resuming can't turn
    /// them on under an excluded app and leaving one can't turn them on while paused.
    /// An unknown frontmost app (nil) never counts as excluded.
    public func allowsActionShortcuts(paused: Bool, frontmost: String?) -> Bool {
        !paused && !contains(frontmost)
    }
}
