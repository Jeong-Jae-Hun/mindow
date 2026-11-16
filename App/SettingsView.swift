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
    @AppStorage(Preferences.restoreOnDisplayChange) private var restoreOnDisplayChange = true
    @AppStorage(Preferences.checkForUpdates) private var checkForUpdates = true
    @State private var trusted = AXIsProcessTrusted()
    @State private var spectacleRunning = SpectacleShortcuts.isSpectacleRunning
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var conflicts = Shortcuts.conflicts()
    private let layouts = LayoutLibrary.shared

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
            AutoPlacementSection()
            Section {
                ForEach(layouts.snapshots.layouts, id: \.id) { layout in
                    VStack(alignment: .leading) {
                        HStack {
                            LayoutNameField(layout: layout)
                            Button("Overwrite with Current Windows", systemImage: "arrow.triangle.2.circlepath") {
                                Task { await layouts.overwrite(layout.id) }
                            }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).help("Overwrite with Current Windows")
                            Button("Delete", systemImage: "minus.circle") { layouts.delete(layout.id) }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                        }
                        recorder("Shortcut", name: Shortcuts.layoutName(layout.id))
                    }
                }
                Button("Save Current Layout…", systemImage: "plus") { Task { await layouts.saveCurrent() } }
            } header: {
                Text("Layouts")
            } footer: {
                Text("Restore from the menu bar, a shortcut, mindow://layout/<name> or the Shortcuts app. Windows are found by app, then title, then order; windows without a match stay put.")
                    .foregroundStyle(.secondary).font(.caption)
            }
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
                Toggle("Restore windows when displays change", isOn: $restoreOnDisplayChange)
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
                HStack {
                    AppLabel(bundleID: bundleID)
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
                guard let bundleID = chooseApp("Choose an app whose shortcuts Mindow should leave alone") else { return }
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

/// Same rule as `ExcludedAppsSection`: a local copy, written only on a user change. The
/// pickers' bindings go through `change` too, so setting the value they show writes nothing.
private struct AutoPlacementSection: View {
    @State private var rules = AppRules.stored
    private let frontmost = Shortcuts.frontmost

    var body: some View {
        Section {
            ForEach(rules.rules, id: \.bundleID) { rule in
                VStack(alignment: .leading) {
                    HStack {
                        AppLabel(bundleID: rule.bundleID)
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") { change { $0.remove(rule.bundleID) } }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                    HStack {
                        Picker("Action", selection: binding(rule, \.action)) {
                            ForEach(AppRule.actions, id: \.self) { Text($0.title).tag($0) }
                        }
                        Picker("Display", selection: binding(rule, \.display)) {
                            Text("Current Display").tag(Int?.none)
                            ForEach(0..<NSScreen.screens.count, id: \.self) { index in
                                Text("Display \(index + 1)").tag(Int?.some(index))
                            }
                            // A display that isn't connected now keeps its choice as one more item.
                            if let display = rule.display, display >= NSScreen.screens.count {
                                // Unnumbered: a hand-edited index can be any size, even Int.max.
                                Text("Display Not Connected").tag(Int?.some(display))
                            }
                        }
                    }
                    .labelsHidden()
                }
            }
            if let app = frontmost.lastOther, let bundleID = app.bundleIdentifier {
                Button("Add Frontmost App (\(app.localizedName ?? bundleID))", systemImage: "plus") {
                    change { $0.add(bundleID) }
                }
                .disabled(rules.rule(for: bundleID) != nil)
            } else {
                Button("Add Frontmost App", systemImage: "plus") {}.disabled(true)
            }
            Button("Choose App…", systemImage: "plus") {
                guard let bundleID = chooseApp("Choose an app whose new windows Mindow should place") else { return }
                change { $0.add(bundleID) }
            }
        } header: {
            Text("Auto Placement")
        } footer: {
            Text("New windows of these apps take the action's place. Displays count from the left. Excluded apps are left alone.")
                .foregroundStyle(.secondary).font(.caption)
        }
    }

    private func binding<Value>(_ rule: AppRule, _ field: WritableKeyPath<AppRule, Value>) -> Binding<Value> {
        Binding(
            get: { rule[keyPath: field] },
            set: { value in
                var next = rule
                next[keyPath: field] = value
                change { $0.update(next) }
            }
        )
    }

    private func change(_ edit: (inout AppRules) -> Void) {
        var next = rules
        edit(&next)
        guard next != rules else { return }
        rules = next
        UserDefaults.standard.set(next.plist, forKey: Preferences.appRules)
    }
}

/// Renames on Return or when the field loses focus, not on every keystroke, so a name
/// cleared to type a new one isn't refused halfway (blank names are ignored).
private struct LayoutNameField: View {
    let layout: LayoutSnapshot
    @State private var text: String
    @FocusState private var focused: Bool

    init(layout: LayoutSnapshot) {
        self.layout = layout
        _text = State(initialValue: layout.name)
    }

    var body: some View {
        TextField("Name", text: $text)
            .labelsHidden()
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            .onChange(of: layout.name) { _, name in
                if name != text { text = name }
            }
    }

    private func commit() {
        LayoutLibrary.shared.change { $0.rename(layout.id, to: text) }
        // A blank or padded name shows the stored one again.
        if let name = LayoutLibrary.shared.snapshots.layout(id: layout.id)?.name, name != text { text = name }
    }
}

// ─── App list helpers ───

/// An app's icon and name, found by bundle ID, or the bare ID when Launch Services
/// can't find it (not installed); the setting still applies by ID.
private struct AppLabel: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                .resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading) {
                Text(url.deletingPathExtension().lastPathComponent)
                Text(bundleID).foregroundStyle(.secondary).font(.caption)
            }
        } else {
            Image(systemName: "questionmark.app").frame(width: 20, height: 20)
            Text(bundleID)
        }
    }
}

/// The bundle ID of an app picked in an open panel. Nil when cancelled; an app without
/// a bundle ID beeps.
@MainActor
private func chooseApp(_ message: String) -> String? {
    let panel = NSOpenPanel()
    panel.message = message
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(filePath: "/Applications")
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
        NSSound.beep()
        return nil
    }
    return bundleID
}
