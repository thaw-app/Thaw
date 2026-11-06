//
//  ThawIntentTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppIntents
import AppKit
import SwiftUI
import Testing
@testable import Thaw

/// Runs body with the intents reading the given app state instead of the live one.
@MainActor
private func withIntentAppState<T>(_ appState: AppState?, _ body: () async throws -> T) async rethrows -> T {
    let previous = IntentAppState.provider
    IntentAppState.provider = { appState }
    defer { IntentAppState.provider = previous }
    return try await body()
}

/// The intents run against an AppState that was never set up, so nothing they do reaches the real menu bar.
@MainActor
@Suite("App Intents", .serialized, .scratchDefaults)
struct ThawIntentTests {
    @Test("The provider reads the live app state by default")
    func defaultProviderIsLive() {
        #expect(thawAppState() === LiveApp.appState)
    }

    @Test("Every intent that needs Thaw reports it is not ready when there is no app state")
    func notReadyWithoutAppState() async {
        await withIntentAppState(nil) {
            await #expect(throws: ThawIntentError.self) { try await HiddenMenuBarItemsSnippet().perform() }
            await #expect(throws: ThawIntentError.self) {
                try await RevealMenuBarItemIntent(itemIdentifier: "x").perform()
            }
            await #expect(throws: ThawIntentError.self) { try await RevealHiddenSectionIntent().perform() }
            await #expect(throws: ThawIntentError.self) { try await ConcealHiddenSectionIntent().perform() }
            var activate = ActivateMenuBarItemIntent()
            activate.item = MenuBarItemEntity(id: "x", name: "X")
            await #expect(throws: ThawIntentError.self) { try await activate.perform() }
            var apply = ApplyProfileIntent()
            apply.profile = ProfileEntity(id: UUID().uuidString, name: "Work")
            await #expect(throws: ThawIntentError.self) { try await apply.perform() }
        }
    }

    @Test("The toggle intents finish quietly when Thaw has not launched yet")
    func togglesWithoutAppState() async throws {
        try await withIntentAppState(nil) {
            _ = try await ToggleHiddenSectionIntent().perform()
            _ = try await ToggleAlwaysHiddenSectionIntent().perform()
            _ = try await ToggleSwapIntent().perform()
            _ = try await ToggleZenModeIntent().perform()
            _ = try await ToggleApplicationMenusIntent().perform()
        }
    }

    @Test("A profile id that is not a UUID is reported as a missing profile")
    func malformedProfileID() async {
        let appState = AppState()
        await withIntentAppState(appState) {
            var intent = ApplyProfileIntent()
            intent.profile = ProfileEntity(id: "not-a-uuid", name: "Old")
            do {
                _ = try await intent.perform()
                Issue.record("Expected the intent to throw")
            } catch let error as ThawIntentError {
                #expect(error == .profileNotFound)
            } catch {
                Issue.record("Unexpected error \(error)")
            }
        }
    }

    @Test("The errors explain themselves to the user")
    func errorMessages() {
        #expect(String(localized: ThawIntentError.appNotReady.localizedStringResource).contains("isn't running"))
        #expect(String(localized: ThawIntentError.profileNotFound.localizedStringResource).contains("no longer exists"))
    }

    @Test("Revealing the hidden section keeps hover from closing it again")
    func revealDisablesHover() async throws {
        let appState = AppState()
        appState.menuBarManager.showOnHoverAllowed = true
        try await withIntentAppState(appState) {
            _ = try await RevealHiddenSectionIntent().perform()
        }
        #expect(!appState.menuBarManager.showOnHoverAllowed)
    }

    @Test("Hiding the section and revealing one item leave hover alone when nothing is set up")
    func concealAndRevealItem() async throws {
        let appState = AppState()
        try await withIntentAppState(appState) {
            _ = try await ConcealHiddenSectionIntent().perform()
            _ = try await RevealMenuBarItemIntent(itemIdentifier: "com.example.item").perform()
        }
        #expect(appState.menuBarManager.showOnHoverAllowed)
        #expect(!appState.menuBarManager.sectionController.isOperational)
    }

    @Test("Toggling the hidden section without a running engine leaves hover reveal on")
    func toggleHiddenWithoutEngine() async throws {
        let appState = AppState()
        try await withIntentAppState(appState) {
            _ = try await ToggleHiddenSectionIntent().perform()
            _ = try await ToggleAlwaysHiddenSectionIntent().perform()
            _ = try await ToggleApplicationMenusIntent().perform()
        }
        #expect(appState.menuBarManager.showOnHoverAllowed)
        #expect(!appState.menuBarManager.isHidingApplicationMenus)
    }

    @Test("Opening an item the app does not know is a no-op")
    func activateUnknownItem() async throws {
        let appState = AppState()
        try await withIntentAppState(appState) {
            var intent = ActivateMenuBarItemIntent()
            intent.item = MenuBarItemEntity(id: "missing", name: "Missing")
            _ = try await intent.perform()
        }
        #expect(appState.itemManager.managedItems.isEmpty)
    }

    @Test("The item query lists nothing before launch or when no items are managed")
    func itemQuery() async throws {
        let query = MenuBarItemEntityQuery()
        let beforeLaunch = try await withIntentAppState(nil) {
            try await query.suggestedEntities()
        }
        #expect(beforeLaunch.isEmpty)
        let (suggested, matched) = try await withIntentAppState(AppState()) {
            try await (query.suggestedEntities(), query.entities(for: ["a", "b"]))
        }
        #expect(suggested.isEmpty)
        #expect(matched.isEmpty)
    }

    @Test("The snippet builds from an empty hidden section")
    func snippetWithNoItems() async throws {
        try await withIntentAppState(AppState()) {
            _ = try await HiddenMenuBarItemsSnippet().perform()
            _ = try await ShowHiddenItemsIntent().perform()
        }
    }

    @Test("Glyph widths stay between the icon height and the row budget")
    func glyphWidthClamp() {
        #expect(HiddenMenuBarItemsSnippetView.clampedGlyphWidth(4) == 18)
        #expect(HiddenMenuBarItemsSnippetView.clampedGlyphWidth(30) == 30)
        #expect(HiddenMenuBarItemsSnippetView.clampedGlyphWidth(400) == 60)
    }

    @Test("The snippet view draws rows, the overflow line and the empty state")
    func snippetViewRenders() throws {
        let rows = [
            HiddenMenuBarItemRow(id: "a", name: "Wi-Fi", glyph: Image(systemName: "wifi"), glyphWidth: 18),
            HiddenMenuBarItemRow(id: "b", name: "Battery", glyph: nil, glyphWidth: 24),
        ]
        let full = OffscreenRender(
            HiddenMenuBarItemsSnippetView(rows: rows, overflowCount: 3, canRevealIndividually: true),
            size: CGSize(width: 360, height: 240)
        )
        let empty = OffscreenRender(
            HiddenMenuBarItemsSnippetView(rows: [], overflowCount: 0, canRevealIndividually: false),
            size: CGSize(width: 360, height: 240)
        )
        #expect(full.host.fittingSize.height > empty.host.fittingSize.height)
        #expect(try full.pixels() != empty.pixels())
    }

    @Test("The entities show their names")
    func entityRepresentation() {
        let entity = MenuBarItemEntity(id: "id", name: "Clock")
        #expect(String(localized: entity.displayRepresentation.title) == "Clock")
    }

    @Test("Thaw publishes seven App Shortcuts")
    func shortcutsList() {
        #expect(ThawShortcuts.appShortcuts.count == 7)
        #expect(ThawShortcuts.shortcutTileColor == .blue)
    }

    @Test("Only the entry point is discoverable; the snippet buttons stay hidden")
    func discoverability() {
        #expect(!RevealMenuBarItemIntent.isDiscoverable)
        #expect(!RevealHiddenSectionIntent.isDiscoverable)
        #expect(!ConcealHiddenSectionIntent.isDiscoverable)
        #expect(RevealMenuBarItemIntent(itemIdentifier: "abc").itemIdentifier == "abc")
    }
}
