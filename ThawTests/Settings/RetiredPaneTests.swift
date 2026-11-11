//
//  RetiredPaneTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Retired pages open where their settings went.
@Suite("Retired pane redirect", .serialized)
@MainActor
struct RetiredPaneTests {
    @Test("A link or saved pane naming a retired page opens its new home", arguments: [
        ("Spaces", SettingsNavigationIdentifier.displays),
        ("Automation", .triggers),
        ("The Lab", .general),
        ("Advanced", .menuBarLayout),
        ("Displays", .displays),
    ])
    func retiredNames(stored: String, pane: SettingsNavigationIdentifier) {
        #expect(SettingsNavigationIdentifier(storedValue: stored) == pane)
    }

    @Test("An unknown pane name opens nothing")
    func unknownName() {
        #expect(SettingsNavigationIdentifier(storedValue: "Nowhere") == nil)
    }

    @Test("A saved Spaces pane opens Displays", .scratchDefaults)
    func restoringSpaces() {
        let store = Defaults.store
        store.set("Spaces", forKey: Defaults.Key.lastSettingsPane.rawValue)
        #expect(AppNavigationState().settingsNavigationIdentifier == .displays)
    }
}
