//
//  SpacesPaneRedirectTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Spaces is a section of Displays & Spaces, so anything that opens Spaces lands there.
@Suite("Spaces pane redirect", .serialized)
@MainActor
struct SpacesPaneRedirectTests {
    private func withStore(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "SpacesPaneRedirectTests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        let previousStore = Defaults.store
        Defaults.store = store
        defer {
            Defaults.store = previousStore
            store.removePersistentDomain(forName: suite)
        }
        try body(store)
    }

    @Test("Selecting Spaces shows and saves Displays")
    func selectingSpaces() throws {
        try withStore { store in
            let navigation = AppNavigationState()
            navigation.settingsNavigationIdentifier = .spaces
            #expect(navigation.settingsNavigationIdentifier == .displays)
            #expect(store.string(forKey: Defaults.Key.lastSettingsPane.rawValue) == "Displays")
        }
    }

    @Test("A saved Spaces pane opens Displays")
    func restoringSpaces() throws {
        try withStore { store in
            store.set("Spaces", forKey: Defaults.Key.lastSettingsPane.rawValue)
            #expect(AppNavigationState().settingsNavigationIdentifier == .displays)
        }
    }
}
