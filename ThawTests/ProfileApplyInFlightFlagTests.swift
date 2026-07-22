//
//  ProfileApplyInFlightFlagTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

@testable import Thaw
import XCTest

/// Characterizes the in-flight profile flag teardown on the no-moves exit of a
/// profile apply.
///
/// A profile apply arms isApplyingProfileLayout so a concurrent saved-layout
/// apply cannot fight it. The normal exit clears the flag. The no-moves exit
/// (taken when the bar is already in the target arrangement, which is the
/// common case on a display reconnect that re-applies the active-display
/// profile) is a separate code path: if it does not run the same teardown the
/// flag leaks true and every later applySavedLayout is skipped with "profile
/// apply in flight", so the saved layout can never be restored for the rest of
/// the session. The field log showed this stick at a display reconnect and
/// disable re-hide while the menu bar churned across three displays.
@MainActor
final class ProfileApplyInFlightFlagTests: XCTestCase {
    private func makeOrder() -> [String: [String]] {
        ["visible": [], "hidden": [], "alwaysHidden": []]
    }

    /// A profile apply that needs no moves must leave the in-flight flag clear.
    /// Red against the pre-fix no-moves exit, which never cleared it.
    func testNoMovesProfileApplyClearsInFlightFlag() {
        let manager = MenuBarItemManager()
        manager.armProfileState(
            source: .profile,
            pinnedHidden: [],
            pinnedAlwaysHidden: [],
            sectionOrder: makeOrder(),
            itemSectionMap: [:],
            itemOrder: makeOrder()
        )
        XCTAssertTrue(manager.isApplyingProfileLayout, "Arming a profile apply must set the in-flight flag")

        manager.concludeProfileApplyWithoutMoves(source: .profile, items: [])

        XCTAssertFalse(
            manager.isApplyingProfileLayout,
            "A profile apply that needs no item moves must clear the in-flight flag"
        )
    }

    /// A .savedOrder apply never arms the profile flag, and the no-moves
    /// conclusion must not toggle it on.
    func testNoMovesSavedOrderApplyLeavesFlagUntouched() {
        let manager = MenuBarItemManager()
        XCTAssertFalse(manager.isApplyingProfileLayout)

        manager.concludeProfileApplyWithoutMoves(source: .savedOrder, items: [])

        XCTAssertFalse(manager.isApplyingProfileLayout)
    }
}
