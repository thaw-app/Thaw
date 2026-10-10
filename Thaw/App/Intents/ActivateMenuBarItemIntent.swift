//
//  ActivateMenuBarItemIntent.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppIntents

/// A menu bar item exposed to Shortcuts and Spotlight so a user can pick one
/// to open. The id is the item's stable uniqueIdentifier; the name is the
/// same display name shown throughout the app.
struct MenuBarItemEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Menu Bar Item"
    }

    /// AppEntity requires a nonisolated, mutable static var. The query
    /// holds no stored state, so there is nothing to race on, the same
    /// rationale as ProfileEntity.defaultQuery.
    static nonisolated(unsafe) var defaultQuery = MenuBarItemEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

/// Lists the currently managed menu bar items. Unlike ProfileEntityQuery,
/// the item inventory lives only in the running app, so the query reads it off
/// the main actor rather than from disk; when Thaw is not ready it returns
/// nothing rather than failing.
struct MenuBarItemEntityQuery: EntityQuery {
    @MainActor
    private func snapshot() -> [MenuBarItemEntity] {
        guard let appState = thawAppState() else { return [] }
        // Shortcuts offers these for activation, so the question is the item
        // palette's: is there anything behind a click? A spacer or the
        // overflow chevron would be a shortcut that silently does nothing.
        return appState.itemManager.managedItems
            .filter(\.isUserActionable)
            .map { MenuBarItemEntity(id: $0.uniqueIdentifier, name: MenuBarItemDisplayName.displayName(for: $0)) }
    }

    func entities(for identifiers: [String]) async throws -> [MenuBarItemEntity] {
        let wanted = Set(identifiers)
        return await snapshot().filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [MenuBarItemEntity] {
        await snapshot()
    }
}

/// Opens a specific menu bar item's menu, revealing it first if it is hidden.
/// This is the automation counterpart of a per-item hotkey.
struct ActivateMenuBarItemIntent: AppIntent {
    static nonisolated(unsafe) var title: LocalizedStringResource = "Open Menu Bar Item"
    static nonisolated(unsafe) var description: IntentDescription? = IntentDescription(
        "Open a menu bar item's menu, revealing it first if it is hidden.",
        categoryName: "Menu Bar"
    )

    @Parameter(title: "Item")
    var item: MenuBarItemEntity

    static nonisolated(unsafe) var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$item)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appState = thawAppState() else { throw ThawIntentError.appNotReady }
        appState.menuBarManager.openItem(withIdentifier: item.id)
        return .result()
    }
}
