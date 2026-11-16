import Foundation

// ─── Settings file ───

/// Mindow's settings as one JSON file, to carry them to another Mac. A versioned shape,
/// not a UserDefaults dump, so a later version can read an older file. Per-Mac settings
/// (menu bar icon, launch at login, update checks) stay out. A field a file leaves out
/// changes nothing on import.
public struct SettingsFile: Equatable, Sendable {
    public static let format = "mindow-settings"
    public static let version = 1
    /// Shortcut names besides the actions' raw values.
    public static let togglePause = "TogglePause"
    public static let layoutPrefix = "Layout_"

    /// Shortcut name to binding; nil (JSON null) is no shortcut.
    public var shortcuts: [String: KeyBinding?]
    public var gap: Double?
    public var dragSnap: Bool?
    public var showHUD: Bool?
    public var restoreOnDisplayChange: Bool?
    public var cycleOnRepeat: Bool?
    public var excludedApps: ExcludedApps?
    public var appRules: AppRules?
    public var layouts: LayoutSnapshots?

    public init(
        shortcuts: [String: KeyBinding?] = [:], gap: Double? = nil, dragSnap: Bool? = nil, showHUD: Bool? = nil,
        restoreOnDisplayChange: Bool? = nil, cycleOnRepeat: Bool? = nil, excludedApps: ExcludedApps? = nil,
        appRules: AppRules? = nil, layouts: LayoutSnapshots? = nil
    ) {
        self.shortcuts = shortcuts
        self.gap = gap
        self.dragSnap = dragSnap
        self.showHUD = showHUD
        self.restoreOnDisplayChange = restoreOnDisplayChange
        self.cycleOnRepeat = cycleOnRepeat
        self.excludedApps = excludedApps
        self.appRules = appRules
        self.layouts = layouts
    }

    /// The window gap slider's range.
    public static let gapRange: ClosedRange<Double> = 0...32

    public enum ReadError: Error, Equatable {
        case notJSON
        /// Valid JSON, but not `{"format": "mindow-settings", "version": n}` with n from 1.
        case notSettingsFile
        /// Written by a newer Mindow; reading it could drop or misread what it added.
        case newerVersion(Int)
    }

    /// What a file sets, and a line for each entry left out (unknown key, shortcut name
    /// or action, wrong type), shown before anything is written, as a Spectacle import does.
    public struct ReadResult: Equatable, Sendable {
        public var settings: SettingsFile
        public var skipped: [String]
    }

    /// `existing` gives the layout ids a `Layout_<id>` shortcut may name when the file
    /// has no `layouts`; with `layouts`, only the file's own ids count, since importing
    /// replaces the list.
    public static func read(_ data: Data, existing: LayoutSnapshots) throws -> ReadResult {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { throw ReadError.notJSON }
        guard let root = object as? [String: Any], root["format"] as? String == format,
              let fileVersion = PlistNumber.index(root["version"]), fileVersion >= 1
        else { throw ReadError.notSettingsFile }
        guard fileVersion <= version else { throw ReadError.newerVersion(fileVersion) }

        var settings = SettingsFile()
        var skipped = root.keys.filter { !Self.keys.contains($0) }.sorted().map { "\($0): unknown setting" }

        if let raw = root["gap"] {
            if let gap = PlistNumber.real(raw).map(Double.init), gapRange.contains(gap) {
                settings.gap = gap
            } else {
                skipped.append("gap: not a number from 0 to 32")
            }
        }
        for (key, field) in Self.flags {
            guard let raw = root[key] else { continue }
            if let flag = Self.flag(raw) {
                settings[keyPath: field] = flag
            } else {
                skipped.append("\(key): not true or false")
            }
        }
        if let raw = root["excludedApps"] {
            if let entries = raw as? [Any] {
                let ids = entries.compactMap { $0 as? String }
                settings.excludedApps = ExcludedApps(ids)
                if ids.count < entries.count { skipped.append("excludedApps: \(entries.count - ids.count) entries that aren't text") }
            } else {
                skipped.append("excludedApps: not a list")
            }
        }
        if let raw = root["appRules"] {
            if let entries = raw as? [Any] {
                settings.appRules = AppRules(plist: entries)
                // One at a time, so each line names the rule; a repeated app is dropped quietly, as stored rules are.
                skipped += entries.filter { AppRules(plist: [$0]).rules.isEmpty }.map { "appRules: \(Self.describeEntry($0))" }
            } else {
                skipped.append("appRules: not a list")
            }
        }
        if let raw = root["layouts"] {
            if let entries = raw as? [Any] {
                let layouts = LayoutSnapshots(plist: entries)
                settings.layouts = layouts
                for entry in entries {
                    guard let kept = LayoutSnapshots(plist: [entry]).layouts.first else {
                        skipped.append("layouts: \(Self.describeEntry(entry))")
                        continue
                    }
                    let written = ((entry as? [String: Any])?["windows"] as? [Any])?.count ?? 0
                    if kept.windows.count < written { skipped.append("layouts: \(written - kept.windows.count) windows of \(kept.name)") }
                }
            } else {
                skipped.append("layouts: not a list")
            }
        }
        if let raw = root["shortcuts"] {
            if let entries = raw as? [String: Any] {
                let layoutIDs = Set((settings.layouts ?? existing).layouts.map(\.id))
                for (name, value) in entries.sorted(by: { $0.key < $1.key }) {
                    guard isShortcutName(name, layoutIDs: layoutIDs) else {
                        skipped.append("shortcuts.\(name): unknown shortcut")
                        continue
                    }
                    if value is NSNull {
                        settings.shortcuts[name] = .some(nil)
                    } else if let entry = value as? [String: Any],
                              let keyCode = PlistNumber.index(entry["carbonKeyCode"]),
                              let modifiers = PlistNumber.index(entry["carbonModifiers"]) {
                        settings.shortcuts[name] = KeyBinding(carbonKeyCode: keyCode, carbonModifiers: modifiers)
                    } else {
                        skipped.append("shortcuts.\(name): not a shortcut or null")
                    }
                }
            } else {
                skipped.append("shortcuts: not an object")
            }
        }
        return ReadResult(settings: settings, skipped: skipped)
    }

    /// Pretty-printed with sorted keys, so two exports of the same settings are the
    /// same file and a diff between Macs reads line by line.
    public func json() throws -> Data {
        var root: [String: Any] = ["format": Self.format, "version": Self.version]
        root["shortcuts"] = shortcuts.mapValues { binding -> Any in
            binding.map { ["carbonKeyCode": $0.carbonKeyCode, "carbonModifiers": $0.carbonModifiers] } ?? NSNull()
        }
        root["gap"] = gap
        for (key, field) in Self.flags {
            root[key] = self[keyPath: field]
        }
        root["excludedApps"] = excludedApps?.bundleIDs
        root["appRules"] = appRules?.plist
        root["layouts"] = layouts?.plist
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    public enum Change: Equatable, Sendable {
        case shortcut(String, from: KeyBinding?, to: KeyBinding?)
        case value(String, from: String, to: String)
    }

    /// What importing this file would change in `current` (what this Mac has now):
    /// fields the file sets to another value, shortcuts by name in name order.
    public func changes(from current: SettingsFile) -> [Change] {
        var changes: [Change] = []
        if let gap, gap != current.gap {
            changes.append(.value("gap", from: current.gap.map(Self.describe) ?? "–", to: Self.describe(gap)))
        }
        for (key, field) in Self.flags {
            guard let value = self[keyPath: field], value != current[keyPath: field] else { continue }
            changes.append(.value(key, from: current[keyPath: field].map(Self.describe) ?? "–", to: Self.describe(value)))
        }
        if let excludedApps, excludedApps != current.excludedApps {
            changes.append(.value("excludedApps", from: Self.describe(current.excludedApps?.bundleIDs ?? []), to: Self.describe(excludedApps.bundleIDs)))
        }
        if let appRules, appRules != current.appRules {
            changes.append(.value("appRules", from: Self.describe(current.appRules), to: Self.describe(appRules)))
        }
        if let layouts, layouts != current.layouts {
            changes.append(.value("layouts", from: Self.describe(current.layouts?.layouts.map(\.name) ?? []), to: Self.describe(layouts.layouts.map(\.name))))
        }
        for (name, binding) in shortcuts.sorted(by: { $0.key < $1.key }) {
            let now = current.shortcuts[name] ?? nil
            if binding != now { changes.append(.shortcut(name, from: now, to: binding)) }
        }
        return changes
    }

    /// Action raw values, TogglePause, and `Layout_<id>` for an id in `layoutIDs`.
    public static func isShortcutName(_ name: String, layoutIDs: Set<String>) -> Bool {
        if WindowAction(rawValue: name) != nil || name == togglePause { return true }
        return name.hasPrefix(layoutPrefix) && layoutIDs.contains(String(name.dropFirst(layoutPrefix.count)))
    }

    // ─── Private ───

    /// Computed: a key path isn't Sendable, so it can't sit in a stored static.
    private static var flags: [(key: String, field: WritableKeyPath<SettingsFile, Bool?>)] {
        [
            ("dragSnap", \.dragSnap), ("showHUD", \.showHUD),
            ("restoreOnDisplayChange", \.restoreOnDisplayChange), ("cycleOnRepeat", \.cycleOnRepeat),
        ]
    }
    private static let keys: Set<String> = Set(["format", "version", "shortcuts", "gap", "excludedApps", "appRules", "layouts"] + flags.map(\.key))

    /// JSON true and false only: a Bool and a number read alike from JSONSerialization,
    /// so 1 is told apart by type.
    private static func flag(_ raw: Any) -> Bool? {
        guard CFGetTypeID(raw as CFTypeRef) == CFBooleanGetTypeID() else { return nil }
        return raw as? Bool
    }

    private static func describe(_ value: Bool) -> String { value ? "on" : "off" }
    private static func describe(_ value: Double) -> String { String(format: "%g pt", value) }
    /// `bundleID Action @display`, the display only when the rule names one.
    private static func describe(_ rules: AppRules?) -> String {
        describe((rules?.rules ?? []).map { rule in "\(rule.bundleID) \(rule.action.rawValue)" + (rule.display.map { " @\($0)" } ?? "") })
    }
    private static func describe(_ list: [String]) -> String { list.isEmpty ? "none" : list.joined(separator: ", ") }

    /// A skipped list entry: its name or bundle ID when it has one.
    private static func describeEntry(_ entry: Any) -> String {
        let dictionary = entry as? [String: Any]
        return (dictionary?["name"] ?? dictionary?["bundleID"]).map { "\($0)" } ?? "an entry that isn't valid"
    }
}
