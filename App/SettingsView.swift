import KeyboardShortcuts
import MindowCore
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Mindow Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @AppStorage(Preferences.cycleOnRepeat) private var cycleOnRepeat = true
    @AppStorage(Preferences.showMenuBarIcon) private var showMenuBarIcon = true
    @State private var trusted = AXIsProcessTrusted()
    @State private var spectacleRunning = SpectacleShortcuts.isSpectacleRunning
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            if !trusted {
                Section {
                    Label("Mindow needs Accessibility access to move windows.", systemImage: "lock.shield")
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        Button("Open System Settings") { NSWorkspace.shared.open(url) }
                    }
                }
            }
            if spectacleRunning {
                Section {
                    Label("Spectacle is running and will fight over the same shortcuts. Quit it to avoid conflicts.",
                          systemImage: "exclamationmark.triangle")
                }
            }
            Section("Shortcuts") {
                ForEach(WindowAction.allCases, id: \.self) { action in
                    if let name = Shortcuts.names[action] {
                        KeyboardShortcuts.Recorder(action.title, name: name)
                    }
                }
                Button("Import from Spectacle…") { SpectacleImporter.run() }
            }
            Section("General") {
                Toggle("Cycle sizes when the same shortcut is pressed again", isOn: $cycleOnRepeat)
                Toggle("Show icon in menu bar", isOn: $showMenuBarIcon)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).foregroundStyle(.red).font(.caption)
                }
                if !showMenuBarIcon {
                    Text("Open Mindow again from Applications to get back here.")
                        .foregroundStyle(.secondary).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 640)
        // Permission and Spectacle can change while the window is open; nothing notifies us.
        .task {
            while !Task.isCancelled {
                trusted = AXIsProcessTrusted()
                spectacleRunning = SpectacleShortcuts.isSpectacleRunning
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
