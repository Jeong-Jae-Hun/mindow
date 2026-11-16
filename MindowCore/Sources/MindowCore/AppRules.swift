import CoreGraphics

/// One app's automatic placement: each new standard window of the app takes
/// `action`'s first-press frame on `display`.
public struct AppRule: Equatable, Sendable {
    public var bundleID: String
    public var action: WindowAction
    /// Index into the screens left to right, from 0. Nil is the screen the window
    /// opened on.
    public var display: Int?

    public init(bundleID: String, action: WindowAction, display: Int? = nil) {
        self.bundleID = bundleID
        self.action = action
        self.display = display
    }

    /// Display indexes a stored rule may name. A Mac drives far fewer screens; the bound
    /// keeps a hand-edited huge number from reaching Settings, which lists it by number.
    public static let displays = 0..<32

    /// Actions a rule can use: those with a frame on one screen from the window alone.
    /// Undo, redo, display moves and Split with Previous Window need history, a second
    /// screen or a second window.
    public static let actions = WindowAction.allCases.filter { action in
        switch action {
        case .undoLastMove, .redoLastMove, .moveToNextDisplay, .moveToPreviousDisplay, .splitWithPrevious: false
        default: true
        }
    }

    /// Where a window at `window` goes, as a frame and an index into `screens` (visible
    /// frames left to right, AX coordinates). A display that isn't connected falls back
    /// to the window's own screen, so a rule made with two monitors still places on one.
    /// Always the first step, like a first press, with the gap tiles use.
    public func placement(for window: CGRect, among screens: [CGRect], gap: CGFloat) -> (frame: CGRect, screen: Int)? {
        guard let own = WindowLayout.screenIndex(for: window, among: screens) else { return nil }
        let index = display.flatMap { screens.indices.contains($0) ? $0 : nil } ?? own
        let context = WindowLayout.Context(window: window, screen: screens[index], previousStep: nil, gap: gap)
        return WindowLayout.placement(for: action, in: context).map { (frame: $0.frame, screen: index) }
    }
}

/// The rules as stored: a plist array of `{bundleID, action, display?}` dictionaries,
/// so `defaults read` shows them as written. One rule per app.
public struct AppRules: Equatable, Sendable {
    public private(set) var rules: [AppRule]

    /// Keeps the first rule of an app that appears twice.
    public init(_ rules: [AppRule] = []) {
        var seen = Set<String>()
        self.rules = rules.filter { !$0.bundleID.isEmpty && seen.insert($0.bundleID).inserted }
    }

    /// Entries that aren't a dictionary, lack a bundle ID, name an action Mindow doesn't
    /// have or `AppRule.actions` leaves out, or give a display outside `AppRule.displays`,
    /// are skipped: a hand edit or a newer version's rule drops that one rule only.
    public init(plist: Any?) {
        let entries = plist as? [Any] ?? []
        self.init(entries.compactMap { entry -> AppRule? in
            guard let dictionary = entry as? [String: Any],
                  let bundleID = dictionary["bundleID"] as? String,
                  let name = dictionary["action"] as? String,
                  let action = WindowAction(rawValue: name), AppRule.actions.contains(action)
            else { return nil }
            guard let raw = dictionary["display"] else { return AppRule(bundleID: bundleID, action: action) }
            guard let display = raw as? Int, AppRule.displays.contains(display) else { return nil }
            return AppRule(bundleID: bundleID, action: action, display: display)
        })
    }

    public var plist: [[String: Any]] {
        rules.map { rule in
            var entry: [String: Any] = ["bundleID": rule.bundleID, "action": rule.action.rawValue]
            if let display = rule.display { entry["display"] = display }
            return entry
        }
    }

    public func rule(for bundleID: String?) -> AppRule? {
        bundleID.flatMap { id in rules.first { $0.bundleID == id } }
    }

    /// A new rule starts as Left Half on the window's own screen. False when nothing
    /// changed (empty or already listed), so the caller can skip the write.
    @discardableResult
    public mutating func add(_ bundleID: String) -> Bool {
        guard !bundleID.isEmpty, rule(for: bundleID) == nil else { return false }
        rules.append(AppRule(bundleID: bundleID, action: .moveToLeftHalf))
        return true
    }

    /// Replaces the rule for the same app; a rule for an app not listed is ignored.
    public mutating func update(_ rule: AppRule) {
        guard let index = rules.firstIndex(where: { $0.bundleID == rule.bundleID }) else { return }
        rules[index] = rule
    }

    public mutating func remove(_ bundleID: String) {
        rules.removeAll { $0.bundleID == bundleID }
    }
}
