//
//  SpacesPaneRedirectTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Spaces is a section of Displays, so anything that opens Spaces lands there.
@Suite("Spaces pane redirect", .serialized)
@MainActor
struct SpacesPaneRedirectTests {
    @Test("Selecting Spaces shows and saves Displays", .scratchDefaults)
    func selectingSpaces() throws {
        let store = Defaults.store
        let navigation = AppNavigationState()
        navigation.settingsNavigationIdentifier = .spaces
        #expect(navigation.settingsNavigationIdentifier == .displays)
        #expect(store.string(forKey: Defaults.Key.lastSettingsPane.rawValue) == "Displays")
    }

    @Test("A saved Spaces pane opens Displays", .scratchDefaults)
    func restoringSpaces() throws {
        let store = Defaults.store
        store.set("Spaces", forKey: Defaults.Key.lastSettingsPane.rawValue)
        #expect(AppNavigationState().settingsNavigationIdentifier == .displays)
    }
}
