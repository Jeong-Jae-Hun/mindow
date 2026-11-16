import AppKit
import KeyboardShortcuts
import MindowCore
import UniformTypeIdentifiers

// ─── Settings file ───

/// Writes and reads `SettingsFile`, to carry settings to another Mac. Importing shows
/// what would change and what the file had that Mindow skips, and writes nothing
/// unless confirmed.
@MainActor
enum SettingsTransfer {
    static func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Mindow Settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try current.json().write(to: url, options: .atomic)
        } catch {
            showError("Could not save \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// True when settings were replaced, so the settings window reloads the lists it
    /// keeps a copy of.
    static func importFile() -> Bool {
        let panel = NSOpenPanel()
        panel.message = "Choose a Mindow settings file"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let file = url.lastPathComponent
        let result: SettingsFile.ReadResult
        do {
            result = try SettingsFile.read(Data(contentsOf: url), existing: LayoutLibrary.shared.snapshots)
        } catch SettingsFile.ReadError.newerVersion(let version) {
            showError("\(file) is from a newer Mindow (settings version \(version)). Update Mindow to import it.")
            return false
        } catch SettingsFile.ReadError.notJSON, SettingsFile.ReadError.notSettingsFile {
            showError("\(file) isn't a Mindow settings file.")
            return false
        } catch {
            showError("Could not read \(file): \(error.localizedDescription)")
            return false
        }

        let changes = result.settings.changes(from: current)
        let skipped = result.skipped.isEmpty ? [] : ["", "Skipped:"] + result.skipped
        let alert = NSAlert()
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 400, height: 220)
        scroll.borderType = .bezelBorder
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.string = (changes.map { describe($0, layouts: result.settings.layouts) } + skipped).joined(separator: "\n")
        }
        alert.accessoryView = scroll
        guard !changes.isEmpty else {
            alert.messageText = "\(file) has nothing that differs from these settings."
            alert.runModal()
            return false
        }
        alert.messageText = "Replace \(changes.count) settings with those in \(file)?"
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        // Fields the file leaves out stay as they are. Layouts go first: dropping one
        // drops its shortcut, and the shortcut names of the layouts kept or added must
        // exist before the file's shortcuts are set. Observers that follow defaults
        // (drag snap, auto placement) pick the rest up themselves.
        let settings = result.settings
        let defaults = UserDefaults.standard
        if let layouts = settings.layouts {
            LayoutLibrary.shared.change { $0 = layouts }
        }
        if let gap = settings.gap { defaults.set(gap, forKey: Preferences.gap) }
        if let dragSnap = settings.dragSnap { defaults.set(dragSnap, forKey: Preferences.dragSnap) }
        if let showHUD = settings.showHUD { defaults.set(showHUD, forKey: Preferences.showHUD) }
        if let restore = settings.restoreOnDisplayChange { defaults.set(restore, forKey: Preferences.restoreOnDisplayChange) }
        if let cycle = settings.cycleOnRepeat { defaults.set(cycle, forKey: Preferences.cycleOnRepeat) }
        if let apps = settings.excludedApps { defaults.set(apps.bundleIDs, forKey: Preferences.excludedApps) }
        if let rules = settings.appRules { defaults.set(rules.plist, forKey: Preferences.appRules) }
        // The registered names, so an action's Spectacle default stays known: clearing
        // one stores "none" instead of removing the key and getting the default back.
        let names = Dictionary(uniqueKeysWithValues: Shortcuts.titled.map { ($0.name.rawValue, $0.name) })
        for (raw, binding) in settings.shortcuts {
            guard let name = names[raw] else { continue }
            KeyboardShortcuts.setShortcut(binding.map(Shortcuts.shortcut), for: name)
        }
        // Applies the new exclusions and layout shortcuts to the app in front right away.
        Shortcuts.sync()
        return true
    }

    /// This Mac's settings, every field set.
    private static var current: SettingsFile {
        let defaults = UserDefaults.standard
        var file = SettingsFile()
        file.shortcuts = Dictionary(uniqueKeysWithValues: Shortcuts.titled.map { ($0.name.rawValue, Shortcuts.binding(for: $0.name)) })
        file.gap = defaults.double(forKey: Preferences.gap)
        file.dragSnap = defaults.bool(forKey: Preferences.dragSnap)
        file.showHUD = defaults.bool(forKey: Preferences.showHUD)
        file.restoreOnDisplayChange = defaults.bool(forKey: Preferences.restoreOnDisplayChange)
        file.cycleOnRepeat = defaults.bool(forKey: Preferences.cycleOnRepeat)
        file.excludedApps = .stored
        file.appRules = .stored
        file.layouts = LayoutLibrary.shared.snapshots
        return file
    }

    private static func describe(_ change: SettingsFile.Change, layouts: LayoutSnapshots?) -> String {
        switch change {
        case .shortcut(let name, let from, let to):
            let layout = (layouts ?? LayoutLibrary.shared.snapshots).layouts.first { SettingsFile.layoutPrefix + $0.id == name }
            let title = WindowAction(rawValue: name)?.title
                ?? (name == SettingsFile.togglePause ? Shortcuts.togglePauseTitle : nil)
                ?? layout.map { "Layout \($0.name)" }
                ?? name
            return "\(title): \(from.map { "\(Shortcuts.shortcut($0))" } ?? "none") → \(to.map { "\(Shortcuts.shortcut($0))" } ?? "none")"
        case .value(let key, let from, let to):
            // The settings window's names for the file's keys.
            let title = switch key {
            case "gap": "Window gap"
            case "dragSnap": "Snap by dragging"
            case "showHUD": "Label after each action"
            case "restoreOnDisplayChange": "Restore when displays change"
            case "cycleOnRepeat": "Cycle sizes"
            case "excludedApps": "Excluded apps"
            case "appRules": "Auto placement"
            case "layouts": "Layouts (a layout left out loses its shortcut)"
            default: key
            }
            return "\(title): \(from) → \(to)"
        }
    }

    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
