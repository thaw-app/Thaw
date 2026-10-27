//
//  RuntimeSectionContextAdapterTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// The context the section engine reads, answered from an AppState that was never set up.
@MainActor
@Suite("Runtime section context adapter", .serialized, .scratchDefaults)
struct RuntimeSectionContextAdapterTests {
    /// The adapter holds the app state weakly, so each test keeps its own reference alive.
    private func makeAdapter(_ appState: AppState) -> RuntimeSectionContextAdapter {
        RuntimeSectionContextAdapter(appState: appState, revealAttribution: RevealAttribution())
    }

    @Test("The settings it forwards come from the app's settings")
    func forwardsSettings() {
        let appState = AppState()
        let adapter = makeAdapter(appState)
        #expect(adapter.isAlwaysHiddenSectionEnabled == appState.settings.isAlwaysHiddenSectionEnabled)
        #expect(adapter.tempShowInterval == appState.settings.tempShowInterval)
        #expect(adapter.experimentalSystemItemHiding == appState.settings.enableExperimentalSystemItemHiding)
        #expect(adapter.enableExperimentalOverflowPrevention == appState.settings.enableExperimentalOverflowPrevention)
    }

    @Test("Debug switches are read from the settings store")
    func debugSwitches() {
        let appState = AppState()
        let adapter = makeAdapter(appState)
        Defaults.set(true, forKey: .diagnosticRestrictionSceneProbes)
        Defaults.set(true, forKey: .enableExperimentalRevealSystemExtras)
        #expect(adapter.diagnosticsEnabled)
        #expect(adapter.revealFollowingEnabled)
        Defaults.set(false, forKey: .diagnosticRestrictionSceneProbes)
        Defaults.set(false, forKey: .enableExperimentalRevealSystemExtras)
        #expect(!adapter.diagnosticsEnabled)
        #expect(!adapter.revealFollowingEnabled)
    }

    @Test("With no items cached every item list is empty")
    func emptyItemLists() {
        let appState = AppState()
        let adapter = makeAdapter(appState)
        #expect(adapter.currentLiveItems().isEmpty)
        #expect(adapter.currentLiveItems(for: .hidden).isEmpty)
        #expect(adapter.lastOnScreenMenuBarItems().isEmpty)
        #expect(adapter.currentGroupSet() == .empty)
    }

    @Test("The saved order keeps known sections and drops unknown keys")
    func savedOrder() {
        let appState = AppState()
        appState.itemManager.savedSectionOrder = [
            "visible": ["a", "b"],
            "hidden": ["c"],
            "Bogus": ["d"],
        ]
        let order = makeAdapter(appState).loadSavedSectionOrder()
        #expect(order[.visible] == ["a", "b"])
        #expect(order[.hidden] == ["c"])
        #expect(order.count == 2)
    }

    @Test("Bar state reads quiet before setup")
    func barState() {
        let appState = AppState()
        let adapter = makeAdapter(appState)
        #expect(!adapter.shouldDeferMenuBarMutation())
        #expect(!adapter.isThawBarShowing())
        #expect(!adapter.isMenuBarHiddenBySystem())
        #expect(adapter.connectedDisplayIDs() == Set(NSScreen.screens.map(\.displayID)))
        if let active = adapter.activeMenuBarDisplayID() {
            #expect(adapter.connectedDisplayIDs().contains(active))
        }
    }

    @Test("A reveal into Always Hidden turns that section on once")
    func enablesAlwaysHidden() {
        let appState = AppState()
        appState.settings.advanced.enableAlwaysHiddenSection = false
        let adapter = makeAdapter(appState)
        adapter.enableAlwaysHiddenSectionRevealIfNeeded()
        #expect(appState.settings.advanced.enableAlwaysHiddenSection)
        adapter.enableAlwaysHiddenSectionRevealIfNeeded()
        #expect(appState.settings.advanced.enableAlwaysHiddenSection)
    }

    @Test("Engine callbacks are safe to run before setup")
    func callbacksBeforeSetup() {
        let appState = AppState()
        let adapter = makeAdapter(appState)
        adapter.setRevealHideTransitionActive(true)
        adapter.setRevealHideTransitionActive(false)
        adapter.updateControlItemStates()
        adapter.mirrorSectionOrder(["a"], for: .visible)
        adapter.runPostRestrictionSceneProbes()
        adapter.prepareRevealedOrder()
        #expect(adapter.completedLiveWalkGeneration == appState.itemManager.onScreenItemSnapshot.completedWalkGeneration)
        #expect(appState.menuBarManager.showOnHoverAllowed)
        #expect(adapter.loadSavedSectionOrder()[.visible] == ["a"])
        adapter.mirrorSectionOrder([], for: .visible)
        #expect(adapter.loadSavedSectionOrder()[.visible] == nil)
    }

    @Test("An item with no known owner falls back to asking whether any menu is open")
    func menuOpenFallback() async {
        let appState = AppState()
        let adapter = makeAdapter(appState)
        let anyOpen = await adapter.isAnyMenuBarItemMenuOpen()
        let forItem = await adapter.isMenuOpen(forItem: "com.example.missing")
        #expect(anyOpen == forItem)
    }
}
