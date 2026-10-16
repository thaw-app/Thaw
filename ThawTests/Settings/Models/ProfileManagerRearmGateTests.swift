//
//  ProfileManagerRearmGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Pins when a profile update re-arms MenuBarItemManager's in-memory
/// active-profile layout cache.
///
/// Without a re-arm, a late-arrival re-sort reverts the bar to the pre-update
/// layout. Re-arm only for the active profile, and only when the update
/// captured a fresh layout.
@Suite("Profile manager re-arm gate")
struct ProfileManagerRearmGateTests {
    @Test("A layout-only update of the active profile re-arms")
    func activeProfileLayoutOnlyUpdateRearms() {
        let id = UUID()

        #expect(ProfileManager.shouldRearmActiveLayout(updatedID: id, activeID: id, scope: .layoutOnly))
    }

    /// An "Update All" on the active profile also captures the layout, so it
    /// must re-arm.
    @Test("An update-all of the active profile re-arms")
    func activeProfileAllUpdateRearms() {
        let id = UUID()

        #expect(ProfileManager.shouldRearmActiveLayout(updatedID: id, activeID: id, scope: .all))
    }

    /// A configuration-only update changes no layout, so it must not touch the
    /// layout cache.
    @Test("A configuration-only update of the active profile does not re-arm")
    func activeProfileConfigurationOnlyDoesNotRearm() {
        let id = UUID()

        #expect(!ProfileManager.shouldRearmActiveLayout(updatedID: id, activeID: id, scope: .configurationOnly))
    }

    /// Updating a profile that is not the active one must never touch live
    /// state, regardless of scope.
    @Test("Updating an inactive profile never re-arms, whatever the scope")
    func inactiveProfileUpdateDoesNotRearm() {
        #expect(!ProfileManager.shouldRearmActiveLayout(updatedID: UUID(), activeID: UUID(), scope: .layoutOnly))
        #expect(!ProfileManager.shouldRearmActiveLayout(updatedID: UUID(), activeID: UUID(), scope: .all))
    }

    @Test("With no active profile there is nothing to re-arm")
    func noActiveProfileDoesNotRearm() {
        let id = UUID()

        #expect(!ProfileManager.shouldRearmActiveLayout(updatedID: id, activeID: nil, scope: .layoutOnly))
        #expect(!ProfileManager.shouldRearmActiveLayout(updatedID: id, activeID: nil, scope: .all))
    }
}
