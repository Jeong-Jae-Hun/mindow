import SwiftUI

@main
struct MindowApp: App {
    var body: some Scene {
        MenuBarExtra("Mindow", systemImage: "rectangle.split.2x2") {
            Button("Quit Mindow") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
