//
//  ProfileApplyInFlightFlagTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Pins the in-flight flag teardown on the no-moves exit of a profile apply.
///
/// A profile apply arms isApplyingProfileLayout so a concurrent saved-layout
/// apply can't fight it. The no-moves exit (common on a display reconnect that
/// re-applies the active-display profile) is a separate path. If it skips the
/// teardown, the flag leaks true and every later applySavedLayout is skipped
/// as "profile apply in flight" for the rest of the session.
///
/// Serialized because each case drives a real profile apply, which touches
/// process-wide menu bar state.
@MainActor
@Suite("Profile apply in-flight flag", .serialized)
struct ProfileApplyInFlightFlagTests {
    private func makeOrder() -> [String: [String]] {
        ["visible": [], "hidden": [], "alwaysHidden": []]
    }

    /// A profile apply that needs no moves must leave the in-flight flag clear.
    @Test("A no-moves profile apply clears the in-flight flag")
    func noMovesProfileApplyClearsInFlightFlag() {
        let manager = MenuBarItemManager()
        manager.armProfileState(
            source: .profile,
            pinnedHidden: [],
            pinnedAlwaysHidden: [],
            sectionOrder: makeOrder(),
            itemSectionMap: [:],
            itemOrder: makeOrder()
        )
        #expect(manager.isApplyingProfileLayout, "Arming a profile apply must set the in-flight flag")

        manager.concludeProfileApplyWithoutMoves(source: .profile, items: [])

        #expect(
            !manager.isApplyingProfileLayout,
            "A profile apply that needs no item moves must clear the in-flight flag"
        )
    }

    /// A .savedOrder apply never arms the profile flag, and the no-moves
    /// conclusion must not toggle it on.
    @Test("A no-moves saved-order apply leaves the flag untouched")
    func noMovesSavedOrderApplyLeavesFlagUntouched() {
        let manager = MenuBarItemManager()
        #expect(!manager.isApplyingProfileLayout)

        manager.concludeProfileApplyWithoutMoves(source: .savedOrder, items: [])

        #expect(!manager.isApplyingProfileLayout)
    }

    /// An empty profile layout has no moves to run, but it still must release
    /// the profile-apply gate so a later saved-layout restore can proceed.
    @Test("An empty profile apply clears the in-flight flag", .timeLimit(.minutes(1)))
    func emptyProfileApplyClearsInFlightFlag() async {
        let manager = MenuBarItemManager()

        await manager.applyProfileLayout(
            MenuBarItemManager.ProfileLayoutSpec(
                pinnedHidden: [],
                pinnedAlwaysHidden: [],
                sectionOrder: makeOrder(),
                itemSectionMap: [:],
                itemOrder: [:]
            )
        )

        #expect(!manager.isApplyingProfileLayout)
    }
}
