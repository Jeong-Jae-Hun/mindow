import AppKit
import MindowCore
import Observation

// ─── Layout library ───

/// The saved layouts (`LayoutSnapshots`) the menu, settings, shortcuts, URLs and the
/// Shortcuts app share. A copy of `mindow.layouts`, written only on a real change, so
/// the menu bar scene that observes it never writes back.
@MainActor @Observable
final class LayoutLibrary {
    static let shared = LayoutLibrary()
    private(set) var snapshots = LayoutSnapshots.stored

    private init() {
        Shortcuts.syncLayouts(snapshots.layouts.map(\.id))
    }

    func change(_ edit: (inout LayoutSnapshots) -> Void) {
        var next = snapshots
        edit(&next)
        guard next != snapshots else { return }
        snapshots = next
        UserDefaults.standard.set(next.plist, forKey: Preferences.layouts)
        Shortcuts.syncLayouts(next.layouts.map(\.id))
    }

    /// Beeps for a layout that no longer exists, such as one a shortcut in the
    /// Shortcuts app still names after it was deleted.
    func restore(id: String) async {
        guard let layout = snapshots.layout(id: id) else {
            NSSound.beep()
            return
        }
        await WindowManager.shared.restore(layout)
    }

    /// `mindow://layout/<name>`: exact name, the first layout that has it.
    func restore(named name: String) async {
        guard let layout = snapshots.first(named: name) else {
            NSSound.beep()
            return
        }
        await WindowManager.shared.restore(layout)
    }

    /// Reads the windows first, so the layout is what was on screen when asked, then asks
    /// for a name. Nothing to save (no Accessibility access, no windows) beeps.
    func saveCurrent() async {
        let windows = await WindowManager.shared.captureLayout()
        guard !windows.isEmpty else {
            NSSound.beep()
            return
        }
        guard let name = askName(count: windows.count) else { return }
        change { $0.add(LayoutSnapshot(name: name, windows: windows)) }
    }

    func overwrite(_ id: String) async {
        guard let layout = snapshots.layout(id: id),
              confirm("Replace the windows saved in “\(layout.name)” with the windows on screen now?", button: "Replace")
        else { return }
        let windows = await WindowManager.shared.captureLayout()
        guard !windows.isEmpty else {
            NSSound.beep()
            return
        }
        change { $0.replaceWindows(of: id, with: windows) }
    }

    /// Its shortcut goes with it (`Shortcuts.syncLayouts`).
    func delete(_ id: String) {
        guard let layout = snapshots.layout(id: id), confirm("Delete the layout “\(layout.name)”?", button: "Delete") else { return }
        change { $0.remove(id) }
    }

    // ─── Alerts ───

    /// Mindow has no window in front when this comes from the menu bar, so it comes
    /// forward first or the alert would open behind the other apps.
    private func askName(count: Int) -> String? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Save Current Layout"
        alert.informativeText = "\(count) windows. Restore them from the Layouts menu, a shortcut, mindow://layout/<name> or the Shortcuts app."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            NSSound.beep()
            return nil
        }
        return name
    }

    private func confirm(_ message: String, button: String) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

extension LayoutSnapshots {
    /// Not tied to the main actor: the Shortcuts app's entity query reads it off it.
    static var stored: LayoutSnapshots {
        LayoutSnapshots(plist: UserDefaults.standard.array(forKey: Preferences.layouts))
    }
}
