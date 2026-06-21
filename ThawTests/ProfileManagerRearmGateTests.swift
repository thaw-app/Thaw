//
//  ProfileManagerRearmGateTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Characterizes the gate that decides whether updating a profile should
/// re-arm MenuBarItemManager's in-memory active-profile layout cache.
///
/// The bug: updating the currently-applied profile (Update Layout / Update
/// All) writes the new layout to disk but never refreshes the cache, so a
/// later late-arrival re-sort reverts the bar to the pre-update spec. The fix
/// re-arms the cache, but only for the active profile and only when the update
/// captured a fresh layout. These tests pin that decision matrix down.
final class ProfileManagerRearmGateTests: XCTestCase {
    /// Updating the active profile's layout must re-arm the cache.
    func testActiveProfileLayoutOnlyUpdateRearms() {
        let id = UUID()
        XCTAssertTrue(
            ProfileManager.shouldRearmActiveLayout(updatedID: id, activeID: id, scope: .layoutOnly)
        )
    }

    /// An "Update All" on the active profile also captures the layout, so it
    /// must re-arm.
    func testActiveProfileAllUpdateRearms() {
        let id = UUID()
        XCTAssertTrue(
            ProfileManager.shouldRearmActiveLayout(updatedID: id, activeID: id, scope: .all)
        )
    }

    /// A configuration-only update changes no layout, so it must not touch the
    /// layout cache.
    func testActiveProfileConfigurationOnlyDoesNotRearm() {
        let id = UUID()
        XCTAssertFalse(
            ProfileManager.shouldRearmActiveLayout(updatedID: id, activeID: id, scope: .configurationOnly)
        )
    }

    /// Updating a profile that is not the active one must never touch live
    /// state, regardless of scope.
    func testInactiveProfileUpdateDoesNotRearm() {
        XCTAssertFalse(
            ProfileManager.shouldRearmActiveLayout(updatedID: UUID(), activeID: UUID(), scope: .layoutOnly)
        )
        XCTAssertFalse(
            ProfileManager.shouldRearmActiveLayout(updatedID: UUID(), activeID: UUID(), scope: .all)
        )
    }

    /// With no active profile there is nothing to re-arm.
    func testNoActiveProfileDoesNotRearm() {
        let id = UUID()
        XCTAssertFalse(
            ProfileManager.shouldRearmActiveLayout(updatedID: id, activeID: nil, scope: .layoutOnly)
        )
        XCTAssertFalse(
            ProfileManager.shouldRearmActiveLayout(updatedID: id, activeID: nil, scope: .all)
        )
    }
}
