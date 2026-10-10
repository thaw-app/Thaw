//
//  ThawActionIntents.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

// App Intents surface for the thaw:// control plane.
//
// Thin clients like thawctl-cli: perform() forwards to HotkeyAction. An
// intent needing more than one line of dispatch belongs in HotkeyAction first.
//
// Parameterized intents live in ApplyProfileIntent.swift and
// HiddenItemsSnippetIntents.swift. ThawShortcuts below registers all of them,
// so the ten-shortcut budget is visible in one place.

import AppIntents
import AppKit

/// Shared lookup of the live AppState for every intent file in this folder.
/// The conditional cast only covers launch ordering.
@MainActor
func thawAppState() -> AppState? {
    (NSApp?.delegate as? AppDelegate)?.appState
}

// MARK: - Actions

struct ToggleHiddenSectionIntent: AppIntent {
    static nonisolated(unsafe) var title: LocalizedStringResource = "Toggle Hidden Menu Bar Items"
    static nonisolated(unsafe) var description: IntentDescription? = IntentDescription(
        "Show or hide the Hidden section of the menu bar.",
        categoryName: "Menu Bar"
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appState = thawAppState() else { return .result() }
        HotkeyAction.toggleHiddenSection.perform(appState: appState)
        return .result()
    }
}

struct ToggleAlwaysHiddenSectionIntent: AppIntent {
    static nonisolated(unsafe) var title: LocalizedStringResource = "Toggle Always Hidden Menu Bar Items"
    static nonisolated(unsafe) var description: IntentDescription? = IntentDescription(
        "Show or hide the Always Hidden section of the menu bar.",
        categoryName: "Menu Bar"
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appState = thawAppState() else { return .result() }
        HotkeyAction.toggleAlwaysHiddenSection.perform(appState: appState)
        return .result()
    }
}

struct ToggleSwapIntent: AppIntent {
    static nonisolated(unsafe) var title: LocalizedStringResource = "Swap Shown and Hidden Items"
    static nonisolated(unsafe) var description: IntentDescription? = IntentDescription(
        "Trade the shown and hidden menu bar items, or trade them back.",
        categoryName: "Menu Bar"
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appState = thawAppState() else { return .result() }
        HotkeyAction.toggleSwap.perform(appState: appState)
        return .result()
    }
}

struct ToggleZenModeIntent: AppIntent {
    static nonisolated(unsafe) var title: LocalizedStringResource = "Toggle Zen Mode"
    static nonisolated(unsafe) var description: IntentDescription? = IntentDescription(
        "Hide every managed menu bar item until toggled again.",
        categoryName: "Menu Bar"
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appState = thawAppState() else { return .result() }
        HotkeyAction.toggleZenMode.perform(appState: appState)
        return .result()
    }
}

struct ToggleApplicationMenusIntent: AppIntent {
    static nonisolated(unsafe) var title: LocalizedStringResource = "Toggle Application Menus"
    static nonisolated(unsafe) var description: IntentDescription? = IntentDescription(
        "Show or hide the frontmost application's menus.",
        categoryName: "Menu Bar"
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appState = thawAppState() else { return .result() }
        HotkeyAction.toggleApplicationMenus.perform(appState: appState)
        return .result()
    }
}

struct OpenThawSettingsIntent: AppIntent {
    static nonisolated(unsafe) var title: LocalizedStringResource = "Open Thaw Settings"
    static nonisolated(unsafe) var description: IntentDescription? = IntentDescription(
        "Open the Thaw settings window.",
        categoryName: "Menu Bar"
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        (NSApp?.delegate as? AppDelegate)?.openSettingsWindow()
        return .result()
    }
}

// MARK: - Shortcut phrases

/// The App Shortcuts Thaw publishes to Siri, Spotlight and the Shortcuts app.
///
/// Only spoken-worthy actions get one; each costs Spotlight and Siri space.
/// Siri matches literally, hence several phrasings. A phrase without
/// \(.applicationName) is dropped at build time.
struct ThawShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor {
        .blue
    }

    static var appShortcuts: [AppShortcut] {
        // Presents the interactive snippet, so it is phrased as both a
        // command and a question.
        AppShortcut(
            intent: ShowHiddenItemsIntent(),
            phrases: [
                "Show hidden menu bar items in \(.applicationName)",
                "What is \(.applicationName) hiding",
                "List \(.applicationName) hidden items",
            ],
            shortTitle: "Show Hidden Items",
            systemImageName: "eye"
        )
        // Without parameterPresentation, an unspoken profile has no options
        // to suggest and the phrase dead-ends.
        AppShortcut(
            intent: ApplyProfileIntent(),
            phrases: [
                "Apply \(\.$profile) profile in \(.applicationName)",
                "Switch \(.applicationName) to \(\.$profile)",
                "Use \(\.$profile) in \(.applicationName)",
            ],
            shortTitle: "Apply Profile",
            systemImageName: "square.stack.3d.up",
            parameterPresentation: ParameterPresentation(
                for: \.$profile,
                summary: Summary("Apply \(\.$profile)"),
                optionsCollections: {
                    OptionsCollection(
                        ProfileEntityQuery(),
                        title: "Menu Bar Profiles",
                        systemImageName: "square.stack.3d.up"
                    )
                }
            )
        )
        AppShortcut(
            intent: ToggleHiddenSectionIntent(),
            phrases: [
                "Toggle hidden menu bar items in \(.applicationName)",
                "Reveal the menu bar with \(.applicationName)",
            ],
            shortTitle: "Toggle Hidden Items",
            systemImageName: "menubar.dock.rectangle"
        )
        AppShortcut(
            intent: ToggleSwapIntent(),
            phrases: [
                "Swap menu bar items in \(.applicationName)",
                "Swap the menu bar with \(.applicationName)",
            ],
            shortTitle: "Swap Items",
            systemImageName: "arrow.left.arrow.right"
        )
        AppShortcut(
            intent: ToggleZenModeIntent(),
            phrases: [
                "Toggle zen mode in \(.applicationName)",
                "Turn on zen mode in \(.applicationName)",
            ],
            shortTitle: "Toggle Zen Mode",
            systemImageName: "leaf"
        )
        AppShortcut(
            intent: ActivateMenuBarItemIntent(),
            phrases: [
                "Open \(\.$item) in \(.applicationName)",
                "Open the \(\.$item) menu bar item with \(.applicationName)",
            ],
            shortTitle: "Open Menu Bar Item",
            systemImageName: "cursorarrow.rays",
            parameterPresentation: ParameterPresentation(
                for: \.$item,
                summary: Summary("Open \(\.$item)"),
                optionsCollections: {
                    OptionsCollection(
                        MenuBarItemEntityQuery(),
                        title: "Menu Bar Items",
                        systemImageName: "menubar.rectangle"
                    )
                }
            )
        )
        AppShortcut(
            intent: OpenThawSettingsIntent(),
            phrases: [
                "Open \(.applicationName) settings",
                "Configure \(.applicationName)",
            ],
            shortTitle: "Open Settings",
            systemImageName: "gearshape"
        )
    }
}
