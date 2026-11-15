import AppKit
import MindowCore
import UniformTypeIdentifiers

/// Reads Spectacle's Shortcuts.json, previews the result, then replaces Mindow's shortcuts.
@MainActor
enum SpectacleImporter {
    static func run() {
        var url: URL? = FileManager.default.homeDirectoryForCurrentUser.appending(path: SpectacleShortcuts.defaultFilePath)
        if let found = url, !FileManager.default.fileExists(atPath: found.path(percentEncoded: false)) {
            let panel = NSOpenPanel()
            panel.message = "Choose Spectacle's Shortcuts.json"
            panel.allowedContentTypes = [.json]
            url = panel.runModal() == .OK ? panel.url : nil
        }
        guard let url else { return }
        let result: SpectacleShortcuts.ImportResult
        do {
            result = try SpectacleShortcuts.parse(Data(contentsOf: url))
        } catch {
            showError("Could not read \(url.lastPathComponent): \(error.localizedDescription)")
            return
        }
        guard !result.bindings.isEmpty else {
            showError("No shortcuts Mindow understands were found in \(url.lastPathComponent).")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Replace \(result.bindings.count) shortcuts with Spectacle's?"
        let lines = WindowAction.allCases.compactMap { action in
            result.bindings[action].map { "\(action.title): \(Shortcuts.shortcut($0))" }
        }
        let skipped = result.skipped.isEmpty ? [] : ["", "Skipped:"] + result.skipped
        alert.informativeText = (lines + skipped).joined(separator: "\n")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Shortcuts.apply(result.bindings)
        UserDefaults.standard.set(Date.now.ISO8601Format(), forKey: Preferences.importedFromSpectacleAt)
    }


    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
