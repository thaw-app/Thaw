//
//  RuntimeSectionContextAdapterFallbackTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// What the section engine reads once the app state it was built from is gone,
/// and how the scene probe finds Thaw's control items among fresh items.
@MainActor
@Suite("Runtime section context adapter fallbacks", .serialized, .scratchDefaults)
struct RuntimeSectionContextAdapterFallbackTests {
    private func item(namespace: String, tagTitle: String, title: String?) -> MenuBarItem {
        MenuBarItem(
            tag: .init(namespace: .string(namespace), title: tagTitle, instanceIndex: 0),
            windowID: 1,
            ownerPID: 99,
            sourcePID: 99,
            bounds: CGRect(x: 100, y: 3, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    /// Builds an adapter whose app state has already been released, after
    /// publishing on-screen items the adapter keeps its own reference to.
    private func makeOrphanedAdapter(onScreen items: [MenuBarItem]) -> (RuntimeSectionContextAdapter, released: Bool) {
        weak var released: AppState?
        let adapter: RuntimeSectionContextAdapter = {
            let appState = AppState()
            released = appState
            appState.itemManager.onScreenItemSnapshot.update(items)
            return RuntimeSectionContextAdapter(appState: appState, revealAttribution: RevealAttribution())
        }()
        return (adapter, released == nil)
    }

    @Test("Once the app state is gone the live lists are empty and the bar reads quiet")
    func releasedAppState() throws {
        let onScreen = item(namespace: "com.example.app", tagTitle: "Status", title: "Status")
        let (adapter, released) = makeOrphanedAdapter(onScreen: [onScreen])
        try #require(released)
        #expect(adapter.currentLiveItems().isEmpty)
        #expect(adapter.currentLiveItems(for: .hidden).isEmpty)
        #expect(!adapter.shouldDeferMenuBarMutation())
        #expect(!adapter.isThawBarShowing())
        #expect(!adapter.isMenuBarHiddenBySystem())
        #expect(adapter.currentGroupSet() == .empty)
        #expect(adapter.loadSavedSectionOrder().isEmpty)
    }

    @Test("The last on-screen items outlive the app state")
    func onScreenItemsOutliveAppState() throws {
        let onScreen = item(namespace: "com.example.app", tagTitle: "Status", title: "Status")
        let (adapter, released) = makeOrphanedAdapter(onScreen: [onScreen])
        try #require(released)
        #expect(adapter.lastOnScreenMenuBarItems().map(\.uniqueIdentifier) == [onScreen.uniqueIdentifier])
    }

    @Test("A control item is found by its accessibility title")
    func controlItemByTitle() {
        let adapter = RuntimeSectionContextAdapter(appState: AppState(), revealAttribution: RevealAttribution())
        let other = item(namespace: "com.example.app", tagTitle: "Status", title: "Status")
        let visible = item(namespace: "com.example.host", tagTitle: "Item-0", title: ControlItemIdentifier.visible.rawValue)
        let found = adapter.controlItem(in: [other, visible], matching: .visible)
        #expect(found?.uniqueIdentifier == visible.uniqueIdentifier)
    }

    @Test("A control item is found by the end of its layout identifier")
    func controlItemByIdentifierSuffix() {
        let adapter = RuntimeSectionContextAdapter(appState: AppState(), revealAttribution: RevealAttribution())
        let hidden = item(namespace: "com.example.host", tagTitle: ControlItemIdentifier.hidden.rawValue, title: nil)
        #expect(hidden.uniqueIdentifier.hasSuffix(":\(ControlItemIdentifier.hidden.rawValue)"))
        let found = adapter.controlItem(in: [hidden], matching: .hidden)
        #expect(found?.uniqueIdentifier == hidden.uniqueIdentifier)
    }

    @Test("Items that only resemble a control item are not taken for one")
    func controlItemMissing() {
        let adapter = RuntimeSectionContextAdapter(appState: AppState(), revealAttribution: RevealAttribution())
        let lookalike = item(
            namespace: "com.example.host",
            tagTitle: "\(ControlItemIdentifier.hidden.rawValue).Copy",
            title: "Thaw.ControlItem"
        )
        #expect(adapter.controlItem(in: [lookalike], matching: .hidden) == nil)
        #expect(adapter.controlItem(in: [], matching: .visible) == nil)
    }
}
