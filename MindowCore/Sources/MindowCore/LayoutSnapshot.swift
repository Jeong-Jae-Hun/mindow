import CoreGraphics
import Foundation

// ─── Layout snapshot ───

/// A saved arrangement of windows that one shortcut, menu item, URL or Shortcuts action
/// puts back. Windows are found again by app, then title, then order, because AX gives
/// no window identity that survives an app relaunch.
public struct LayoutSnapshot: Equatable, Sendable {
    public struct Window: Equatable, Sendable {
        public var bundleID: String
        public var title: String
        /// Position among the app's saved windows (standard, not minimized, not full
        /// screen) in the order the app lists them, front first.
        public var index: Int
        /// Index into the screens left to right, from 0.
        public var display: Int
        /// Relative to that display's visible frame origin, in AX coordinates.
        public var frame: CGRect
        /// The display's visible size when saved. Nil (a hand-written entry) counts as
        /// the size it has now, so the frame isn't scaled.
        public var screen: CGSize?

        public init(bundleID: String, title: String, index: Int, display: Int, frame: CGRect, screen: CGSize? = nil) {
            self.bundleID = bundleID
            self.title = title
            self.index = index
            self.display = display
            self.frame = frame
            self.screen = screen
        }

        /// A window at `window` (AX coordinates), saved on the screen that holds most of
        /// it among `screens` (visible frames left to right).
        public init?(bundleID: String, title: String, index: Int, window: CGRect, among screens: [CGRect]) {
            guard let display = WindowLayout.screenIndex(for: window, among: screens) else { return nil }
            let screen = screens[display]
            self.init(
                bundleID: bundleID, title: title, index: index, display: display,
                frame: window.offsetBy(dx: -screen.minX, dy: -screen.minY), screen: screen.size
            )
        }

        /// Where the window goes now: exactly where it was on the same display, even
        /// partly off it or across two, or scaled and kept on it like Next Display when
        /// that display's visible frame has another size. Nil when that display isn't
        /// connected; the window then stays put.
        public func placement(among screens: [CGRect]) -> (frame: CGRect, screen: Int)? {
            guard screens.indices.contains(display) else { return nil }
            let to = screens[display]
            guard let screen, screen != to.size else { return (frame.offsetBy(dx: to.minX, dy: to.minY), display) }
            return (WindowLayout.moveProportionally(frame, between: (CGRect(origin: .zero, size: screen), to)), display)
        }
    }

    /// A UUID string; the shortcut name `Layout_<id>` and the Shortcuts app keep it, so
    /// renaming doesn't lose either.
    public var id: String
    public var name: String
    public var windows: [Window]

    public init(id: String = UUID().uuidString, name: String, windows: [Window]) {
        self.id = id
        self.name = name
        self.windows = windows
    }

    /// Apps in the order their first window was saved.
    public var bundleIDs: [String] {
        var seen = Set<String>()
        return windows.map(\.bundleID).filter { seen.insert($0).inserted }
    }

    /// Pairs one app's saved windows with the windows it has now (`live`, in the app's
    /// order). Same titles pair first, in index order, so two windows with one title
    /// pair up in turn; an empty title never matches by title. The rest pair by order:
    /// saved by index, live as listed. Whatever is left on either side isn't paired, so
    /// those windows stay where they are.
    public static func match<Live>(_ saved: [Window], live: [(window: Live, title: String)]) -> [(live: Live, saved: Window)] {
        var unpaired = Array(live.indices)
        var pairs: [(live: Int, saved: Window)] = []
        var leftover: [Window] = []
        for window in saved.sorted(by: { $0.index < $1.index }) {
            if !window.title.isEmpty, let position = unpaired.firstIndex(where: { live[$0].title == window.title }) {
                pairs.append((unpaired.remove(at: position), window))
            } else {
                leftover.append(window)
            }
        }
        pairs += zip(unpaired, leftover).map { (live: $0, saved: $1) }
        return pairs.map { (live: live[$0.live].window, saved: $0.saved) }
    }
}

// ─── Stored layouts ───

/// The layouts as stored in `mindow.layouts`: a plist array of `{id, name, windows}`
/// dictionaries, windows as `{bundleID, title, index, display, frame: [x, y, w, h],
/// screen: [w, h]}`, like app rules, so `defaults read` and a settings file show them
/// as written.
public struct LayoutSnapshots: Equatable, Sendable {
    public private(set) var layouts: [LayoutSnapshot]

    /// Keeps the first layout of an id that appears twice, and drops layouts whose id
    /// isn't a UUID (it becomes a shortcut name, which can't hold a dot) or whose name is
    /// blank.
    public init(_ layouts: [LayoutSnapshot] = []) {
        var seen = Set<String>()
        self.layouts = layouts.filter { layout in
            UUID(uuidString: layout.id) != nil && !Self.trimmed(layout.name).isEmpty && seen.insert(layout.id).inserted
        }
    }

    /// Skips a layout without a valid id, a name or a windows list, and inside a layout
    /// each window whose fields are missing or of the wrong type: a hand edit or a newer
    /// version's entry drops that one entry only.
    public init(plist: Any?) {
        let entries = plist as? [Any] ?? []
        self.init(entries.compactMap { entry -> LayoutSnapshot? in
            guard let dictionary = entry as? [String: Any],
                  let id = dictionary["id"] as? String,
                  let name = dictionary["name"] as? String,
                  let windows = dictionary["windows"] as? [Any]
            else { return nil }
            return LayoutSnapshot(id: id, name: name, windows: windows.compactMap(Self.window))
        })
    }

    public var plist: [[String: Any]] {
        layouts.map { layout in
            [
                "id": layout.id,
                "name": layout.name,
                "windows": layout.windows.map { window in
                    var entry: [String: Any] = [
                        "bundleID": window.bundleID, "title": window.title, "index": window.index, "display": window.display,
                        "frame": [window.frame.minX, window.frame.minY, window.frame.width, window.frame.height].map(Double.init),
                    ]
                    if let screen = window.screen { entry["screen"] = [screen.width, screen.height].map(Double.init) }
                    return entry
                },
            ]
        }
    }

    public func layout(id: String) -> LayoutSnapshot? {
        layouts.first { $0.id == id }
    }

    /// Exact and case-sensitive, as a URL spells it; the first of two with one name.
    public func first(named name: String) -> LayoutSnapshot? {
        layouts.first { $0.name == name }
    }

    /// The name is trimmed. False when nothing was added (blank name, id taken or not a UUID).
    @discardableResult
    public mutating func add(_ layout: LayoutSnapshot) -> Bool {
        var layout = layout
        layout.name = Self.trimmed(layout.name)
        let next = LayoutSnapshots(layouts + [layout])
        guard next.layouts.count > layouts.count else { return false }
        self = next
        return true
    }

    /// A blank name is ignored; the name is trimmed.
    public mutating func rename(_ id: String, to name: String) {
        let name = Self.trimmed(name)
        guard !name.isEmpty, let index = layouts.firstIndex(where: { $0.id == id }) else { return }
        layouts[index].name = name
    }

    public mutating func replaceWindows(of id: String, with windows: [LayoutSnapshot.Window]) {
        guard let index = layouts.firstIndex(where: { $0.id == id }) else { return }
        layouts[index].windows = windows
    }

    public mutating func remove(_ id: String) {
        layouts.removeAll { $0.id == id }
    }

    private static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func window(_ entry: Any) -> LayoutSnapshot.Window? {
        guard let dictionary = entry as? [String: Any],
              let bundleID = dictionary["bundleID"] as? String, !bundleID.isEmpty,
              let title = dictionary["title"] as? String,
              let index = PlistNumber.index(dictionary["index"]),
              let display = PlistNumber.index(dictionary["display"]),
              let rawFrame = dictionary["frame"] as? [Any], rawFrame.count == 4,
              case let frame = rawFrame.compactMap(PlistNumber.real), frame.count == 4, frame[2] > 0, frame[3] > 0
        else { return nil }
        var screen: CGSize?
        if let raw = dictionary["screen"] {
            guard let rawSize = raw as? [Any], rawSize.count == 2,
                  case let size = rawSize.compactMap(PlistNumber.real), size.count == 2, size[0] > 0, size[1] > 0
            else { return nil }
            screen = CGSize(width: size[0], height: size[1])
        }
        return LayoutSnapshot.Window(
            bundleID: bundleID, title: title, index: index, display: display,
            frame: CGRect(x: frame[0], y: frame[1], width: frame[2], height: frame[3]), screen: screen
        )
    }
}

// ─── Plist numbers ───

/// Numbers read from a plist or JSON, where a Bool bridges to a number (true is 1), so
/// it is ruled out by type first.
enum PlistNumber {
    static func real(_ raw: Any?) -> CGFloat? {
        guard let raw, CFGetTypeID(raw as CFTypeRef) != CFBooleanGetTypeID(),
              let number = raw as? NSNumber, number.doubleValue.isFinite
        else { return nil }
        return CGFloat(number.doubleValue)
    }

    /// A whole number from 0.
    static func index(_ raw: Any?) -> Int? {
        guard let raw, CFGetTypeID(raw as CFTypeRef) != CFBooleanGetTypeID(), let value = raw as? Int, value >= 0 else { return nil }
        return value
    }
}
