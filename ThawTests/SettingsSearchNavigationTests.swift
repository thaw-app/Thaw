//
//  SettingsSearchNavigationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers `SettingsSearchNavigation`, which exists to stop a disclosure
/// request from one search result leaking into a later, unrelated
/// navigation — a request armed by a search result must be consumed by the
/// pane that asked for it, or dropped.
@MainActor
@Suite("Settings search navigation")
struct SettingsSearchNavigationTests {
    /// A real indexed row that asks for a disclosure group, so the test
    /// tracks the actual index rather than a synthetic entry.
    private var gatedEntry: SearchEntry? {
        SearchIndex.entries.first { $0.disclosure != nil }
    }

    private var plainEntry: SearchEntry? {
        SearchIndex.entries.first { $0.disclosure == nil }
    }

    // MARK: - selectSearchResult

    @Test("Selecting a gated result navigates and arms its disclosure")
    func selectingGatedResultArmsDisclosure() throws {
        let entry = try #require(gatedEntry)
        let state = AppNavigationState()
        var query = "over"

        SettingsSearchNavigation.selectSearchResult(entry, navigationState: state, query: &query)

        #expect(state.settingsNavigationIdentifier == entry.pane)
        #expect(state.requestedSettingsDisclosure == entry.disclosure)
        #expect(query.isEmpty, "the query is cleared so the field does not reopen the result list")
    }

    @Test("Selecting an ungated result clears any standing disclosure")
    func selectingUngatedResultClearsDisclosure() throws {
        // A stale request from an earlier search must not survive into a
        // result that never asked for one.
        let entry = try #require(plainEntry)
        let state = AppNavigationState()
        state.requestedSettingsDisclosure = .advancedLayoutControls
        var query = "x"

        SettingsSearchNavigation.selectSearchResult(entry, navigationState: state, query: &query)

        #expect(state.requestedSettingsDisclosure == nil)
    }

    // MARK: - selectSidebarPane

    @Test("Choosing a pane from the sidebar disarms any disclosure")
    func sidebarSelectionDisarmsDisclosure() {
        // The user navigating by hand is not the search result's pane
        // arriving, so the pending request is abandoned.
        let state = AppNavigationState()
        state.requestedSettingsDisclosure = .advancedLayoutControls

        SettingsSearchNavigation.selectSidebarPane(.hotkeys, navigationState: state)

        #expect(state.requestedSettingsDisclosure == nil)
        #expect(state.settingsNavigationIdentifier == .hotkeys)
    }

    @Test("Re-selecting the current pane still disarms, without renavigating")
    func reselectingCurrentPaneDisarmsOnly() {
        let state = AppNavigationState()
        state.settingsNavigationIdentifier = .advanced
        state.requestedSettingsDisclosure = .advancedLayoutControls

        SettingsSearchNavigation.selectSidebarPane(.advanced, navigationState: state)

        #expect(state.requestedSettingsDisclosure == nil)
        #expect(state.settingsNavigationIdentifier == .advanced)
    }

    // MARK: - consumeDisclosure

    @Test("The pane that was asked for consumes the request exactly once")
    func disclosureIsConsumedOnce() {
        // Once-only is the whole point: a request left armed would fire
        // again the next time the same pane is shown for any reason.
        let state = AppNavigationState()
        state.requestedSettingsDisclosure = .advancedLayoutControls

        #expect(SettingsSearchNavigation.consumeDisclosure(
            .advancedLayoutControls,
            navigationState: state
        ))
        #expect(state.requestedSettingsDisclosure == nil)
        #expect(!SettingsSearchNavigation.consumeDisclosure(
            .advancedLayoutControls,
            navigationState: state
        ))
    }

    @Test("Nothing is consumed when no disclosure was requested")
    func nothingToConsume() {
        let state = AppNavigationState()

        #expect(!SettingsSearchNavigation.consumeDisclosure(
            .advancedLayoutControls,
            navigationState: state
        ))
    }
}
