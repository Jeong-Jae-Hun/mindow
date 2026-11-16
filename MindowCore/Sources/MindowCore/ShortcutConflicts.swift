/// Shortcuts recorded more than once inside Mindow. KeyboardShortcuts runs every name
/// whose shortcut matches the press, in no fixed order, so one key would move the
/// window twice or pause before or after moving it. Shortcuts macOS
/// holds are the recorder's job: KeyboardShortcuts asks before saving one of them.
public enum ShortcutConflicts {
    /// Each name whose binding another name also has, mapped to those other names.
    /// Names without a binding (nil) never conflict.
    public static func find<Name: Hashable>(in bindings: [Name: KeyBinding?]) -> [Name: Set<Name>] {
        let groups = Dictionary(grouping: bindings.compactMap { name, binding in binding.map { (name, $0) } }) { $0.1 }
        var conflicts: [Name: Set<Name>] = [:]
        for group in groups.values where group.count > 1 {
            let names = Set(group.map(\.0))
            for name in names {
                conflicts[name] = names.subtracting([name])
            }
        }
        return conflicts
    }
}
