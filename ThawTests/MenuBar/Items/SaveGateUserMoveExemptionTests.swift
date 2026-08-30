//
//  SaveGateUserMoveExemptionTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterizes the save gate's user-move exemption.
///
/// The exemption exists so a Layout-editor drag becomes the saved order even
/// though it lands inside the five-second move cooldown that otherwise holds
/// saves back while a restore is in flight. The exemption must key on the
/// user's move being the *most recent* move, not merely a recent one: a user
/// drag at T0 followed by an automatic move at T+3 leaves both timestamps
/// inside the window, and exempting then would let the next cache cycle
/// persist an arrangement Thaw generated itself.
@Suite("Save gate user-move exemption")
struct SaveGateUserMoveExemptionTests {
    /// Instants far enough apart that ordering is unambiguous without
    /// depending on the wall clock.
    private func at(seconds: Int64) -> ContinuousClock.Instant {
        ContinuousClock().now.advanced(by: .seconds(seconds))
    }

    /// The case the exemption exists for: the user's drag is the latest move.
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

    /// The regression: a user move followed by an automatic move must not
    /// keep the exemption alive — the latest move is Thaw's, so the cooldown
    /// has to hold against the generated intermediate arrangement.
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
