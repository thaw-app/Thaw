//
//  SaveGateUserMoveExemptionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The save gate's user-move exemption lets a Layout-editor drag become the
/// saved order inside the five-second move cooldown.
///
/// It must require the user's move to be the latest one: after a user drag at
/// T0 and an automatic move at T+3, exempting would persist Thaw's own arrangement.
@Suite("Save gate user-move exemption")
struct SaveGateUserMoveExemptionTests {
    /// Fixed instants, so ordering does not depend on the wall clock.
    private func at(seconds: Int64) -> ContinuousClock.Instant {
        ContinuousClock().now.advanced(by: .seconds(seconds))
    }

    @Test("A user move that is the latest move is exempt")
    func latestUserMoveIsExempt() {
        #expect(MenuBarItemManager.saveCooldownExemptForUserMove(
            lastMoveOperationTimestamp: at(seconds: 10),
            lastUserMoveOperationTimestamp: at(seconds: 10)
        ))
        #expect(MenuBarItemManager.saveCooldownExemptForUserMove(
            lastMoveOperationTimestamp: at(seconds: 9),
            lastUserMoveOperationTimestamp: at(seconds: 10)
        ))
    }

    /// The latest move is Thaw's, so the cooldown must hold against its intermediate arrangement.
    @Test("An automatic move after the user's move is not exempt")
    func automaticMoveAfterUserMoveIsNotExempt() {
        #expect(!MenuBarItemManager.saveCooldownExemptForUserMove(
            lastMoveOperationTimestamp: at(seconds: 13),
            lastUserMoveOperationTimestamp: at(seconds: 10)
        ))
    }

    @Test("No user move ever recorded is not exempt")
    func noUserMoveIsNotExempt() {
        #expect(!MenuBarItemManager.saveCooldownExemptForUserMove(
            lastMoveOperationTimestamp: at(seconds: 10),
            lastUserMoveOperationTimestamp: nil
        ))
    }

    @Test("No move at all is not exempt")
    func noMoveIsNotExempt() {
        #expect(!MenuBarItemManager.saveCooldownExemptForUserMove(
            lastMoveOperationTimestamp: nil,
            lastUserMoveOperationTimestamp: nil
        ))
    }
}
