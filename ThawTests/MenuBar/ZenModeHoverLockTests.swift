//
//  ZenModeHoverLockTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Zen Mode keeps hover from revealing hidden items until it is turned off.
@MainActor
@Suite("Zen Mode hover lock", .serialized)
struct ZenModeHoverLockTests {
    private func withManager(_ body: (MenuBarManager) throws -> Void) throws {
        let suite = "ZenModeHoverLockTests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        let previousStore = Defaults.store
        Defaults.store = store
        defer {
            Defaults.store = previousStore
            store.removePersistentDomain(forName: suite)
        }
        try body(AppState().menuBarManager)
    }

    @Test("Hiding a section or rearming hover doesn't unlock hover during Zen Mode")
    func hoverStaysLocked() throws {
        try withManager { manager in
            manager.toggleZenMode()
            manager.showOnHoverAllowed = true
            #expect(!manager.showOnHoverAllowed)
        }
    }

    @Test("Leaving Zen Mode allows hover again")
    func leavingUnlocks() throws {
        try withManager { manager in
            manager.toggleZenMode()
            manager.toggleZenMode()
            #expect(manager.showOnHoverAllowed)
            manager.showOnHoverAllowed = false
            manager.showOnHoverAllowed = true
            #expect(manager.showOnHoverAllowed)
        }
    }
}
