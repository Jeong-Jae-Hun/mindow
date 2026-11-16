import AppIntents
import MindowCore

// ─── Shortcuts app ───

/// Moves the front window the way the action's shortcut does. It runs without
/// bringing Mindow forward and, like URLs, while shortcuts are paused.
struct MoveWindowIntent: AppIntent {
    static let title: LocalizedStringResource = "Move Window"
    static let description = IntentDescription("Moves the front window the way the Mindow shortcut for the action does.")
    static let openAppWhenRun = false

    @Parameter(title: "Action")
    var action: WindowActionEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Move window: \(\.$action)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        WindowManager.shared.performOnFrontmost(action.action)
        return .result()
    }
}

/// An entity rather than an `AppEnum`: the build reads enum cases from source literals
/// and rejects an enum from another module, so `WindowAction` would need a copy here
/// that could drift. The query lists `allCases` with their titles instead.
struct WindowActionEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Window Action"
    static let defaultQuery = WindowActionQuery()

    let action: WindowAction
    /// Saved in shortcuts, so it is the stable raw value, not the title.
    var id: String { action.rawValue }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(action.title)") }
}

struct WindowActionQuery: EnumerableEntityQuery {
    func allEntities() async throws -> [WindowActionEntity] {
        WindowAction.allCases.map(WindowActionEntity.init)
    }

    func entities(for identifiers: [String]) async throws -> [WindowActionEntity] {
        identifiers.compactMap { WindowAction(rawValue: $0).map(WindowActionEntity.init) }
    }
}

struct MindowShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MoveWindowIntent(),
            phrases: [
                "Move window with \(.applicationName)",
                "\(\.$action) with \(.applicationName)",
            ],
            shortTitle: "Move Window",
            systemImageName: "rectangle.split.2x2"
        )
    }
}
