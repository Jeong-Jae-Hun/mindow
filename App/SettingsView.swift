import KeyboardShortcuts
import MindowCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController {
    private let updates: UpdateChecker
    private var window: NSWindow?

    init(updates: UpdateChecker) {
        self.updates = updates
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(updates: updates)))
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
    let updates: UpdateChecker
    @AppStorage(Preferences.cycleOnRepeat) private var cycleOnRepeat = true
    @AppStorage(Preferences.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(Preferences.gap) private var gap = 0.0
    @AppStorage(Preferences.dragSnap) private var dragSnap = true
    @AppStorage(Preferences.showHUD) private var showHUD = true
    @AppStorage(Preferences.checkForUpdates) private var checkForUpdates = true
    @State private var trusted = AXIsProcessTrusted()
    @State private var spectacleRunning = SpectacleShortcuts.isSpectacleRunning
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var conflicts = Shortcuts.conflicts()

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
                recorder(Shortcuts.togglePauseTitle, name: Shortcuts.togglePause)
                Button("Import from Spectacle…") { SpectacleImporter.run() }
            }
            ForEach(WindowAction.Family.allCases, id: \.self) { family in
                Section(family.title) {
                    ForEach(family.actions, id: \.self) { action in
                        if let name = Shortcuts.names[action] {
                            recorder(action.title, name: name)
                        }
                    }
                }
            }
            ExcludedAppsSection()
            Section("General") {
                Toggle("Cycle sizes when the same shortcut is pressed again", isOn: $cycleOnRepeat)
                // Even steps keep the half gap between neighbours on whole points.
                LabeledContent("Window gap") {
                    HStack {
                        Slider(value: $gap, in: 0...32, step: 2)
                        Text("\(Int(gap)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("Snap windows by dragging to screen edges", isOn: $dragSnap)
                if dragSnap {
                    Text("Left and right edges take half the screen, the top edge all of it, corners a quarter. Turn off \"Drag windows to screen edges to tile\" in System Settings > Desktop & Dock so macOS doesn't tile them too.")
                        .foregroundStyle(.secondary).font(.caption)
                }
                Toggle("Show a brief label after each action", isOn: $showHUD)
                Toggle("Show icon in menu bar", isOn: $showMenuBarIcon)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
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
                if let loginError {
                    Text(loginError).foregroundStyle(.red).font(.caption)
                }
                if !showMenuBarIcon {
                    Text("Open Mindow again from Applications to get back here.")
                        .foregroundStyle(.secondary).font(.caption)
                }
                Toggle("Check for updates", isOn: $checkForUpdates)
                    .onChange(of: checkForUpdates) { Task { await updates.refresh() } }
                if let release = updates.available {
                    HStack {
                        Text("v\(release.version.description) available — brew upgrade --cask mindow")
                            .textSelection(.enabled)
                        Spacer()
                        Button("Open Release Page") { NSWorkspace.shared.open(release.url) }
                    }
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
        // KeyboardShortcuts posts its own change notification only internally, and the
        // recorder's onChange misses Spectacle imports, so any defaults write rechecks.
        // Only @State is written here, never UserDefaults, so this can't feed itself.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: DispatchQueue.main)) { _ in
            let next = Shortcuts.conflicts()
            if next != conflicts { conflicts = next }
        }
    }

    private func recorder(_ title: String, name: KeyboardShortcuts.Name) -> some View {
        LabeledContent(title) {
            HStack {
                if let others = conflicts[name] {
                    let text = "Also used by: \(others.joined(separator: ", "))"
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help(text)
                        .accessibilityLabel(text)
                }
                KeyboardShortcuts.Recorder(for: name)
            }
        }
    }
}

/// Edits a local copy and writes UserDefaults only on a user change, never from a binding.
private struct ExcludedAppsSection: View {
    @State private var apps = ExcludedApps.stored
    private let frontmost = Shortcuts.frontmost

    var body: some View {
        Section {
            ForEach(apps.bundleIDs, id: \.self) { bundleID in
                let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                HStack {
                    if let url {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                            .resizable().frame(width: 20, height: 20)
                        VStack(alignment: .leading) {
                            Text(url.deletingPathExtension().lastPathComponent)
                            Text(bundleID).foregroundStyle(.secondary).font(.caption)
                        }
                    } else {
                        // Not installed (or not found by Launch Services); still excluded by ID.
                        Image(systemName: "questionmark.app").frame(width: 20, height: 20)
                        Text(bundleID)
                    }
                    Spacer()
                    Button("Remove", systemImage: "minus.circle") { change { $0.remove(bundleID) } }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                }
            }
            if let app = frontmost.lastOther, let bundleID = app.bundleIdentifier {
                Button("Add Frontmost App (\(app.localizedName ?? bundleID))", systemImage: "plus") {
                    change { $0.add(bundleID) }
                }
                .disabled(apps.contains(bundleID))
            } else {
                Button("Add Frontmost App", systemImage: "plus") {}.disabled(true)
            }
            Button("Choose App…", systemImage: "plus") {
                let panel = NSOpenPanel()
                panel.message = "Choose an app whose shortcuts Mindow should leave alone"
                panel.allowedContentTypes = [.application]
                panel.directoryURL = URL(filePath: "/Applications")
                guard panel.runModal() == .OK, let url = panel.url else { return }
                guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
                    NSSound.beep()
                    return
                }
                change { $0.add(bundleID) }
            }
        } header: {
            Text("Excluded Apps")
        } footer: {
            Text("Window shortcuts are off while one of these apps is in front, so the keys reach it. The menu bar items still work.")
                .foregroundStyle(.secondary).font(.caption)
        }
    }

    private func change(_ edit: (inout ExcludedApps) -> Void) {
        var next = apps
        edit(&next)
        guard next != apps else { return }
        apps = next
        UserDefaults.standard.set(next.bundleIDs, forKey: Preferences.excludedApps)
        // Applies the new list to the app in front right away.
        Shortcuts.sync()
    }
}
