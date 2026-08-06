//
//  MoveOperationTimeoutTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterizes how a move attempt's outcome sizes the next attempt's
/// budget.
///
/// `postMoveEvents` waits for the item's origin to change, not for it to
/// arrive: an attempt that misses its destination still displaces the item
/// by a pixel or two as the owning app registers the click. Treating that
/// as a fast response and shortening the budget let a run of misses starve
/// an item until it could no longer answer in time — the
/// `itemResponseTimeout` cascade behind #881.
@Suite("Move operation timeout")
struct MoveOperationTimeoutTests {
    /// Landing the item is the only outcome that earns a shorter budget.
    @Test("Landing the item shrinks the budget by a quarter")
    func landingShrinksTheBudget() {
        #expect(
            MenuBarItemManager.nextMoveOperationTimeout(
                after: .milliseconds(100), outcome: .landed
            ) == .milliseconds(75)
        )
    }

    /// An unresponsive owner earns a longer budget, unchanged from before.
    @Test("An unresponsive owner grows the budget by half")
    func unresponsiveOwnerGrowsTheBudget() {
        #expect(
            MenuBarItemManager.nextMoveOperationTimeout(
                after: .milliseconds(100), outcome: .ownerDidNotRespond
            ) == .milliseconds(150)
        )
    }

    /// The fix: a miss is neutral. It is neither evidence the owner is
    /// keeping up nor evidence it has stopped answering.
    @Test("Displacing the item without landing it leaves the budget alone")
    func missIsNeutral() {
        #expect(
            MenuBarItemManager.nextMoveOperationTimeout(
                after: .milliseconds(100), outcome: .displacedWithoutLanding
            ) == .milliseconds(100)
        )
    }

    /// Regression lock for #881. UserSwitcher drifted 1144 → 1142 → 1140 →
    /// 1138 → 1137 across three attempts that each displaced it without
    /// landing it, then timed out. Under the old unconditional decay each of
    /// those misses shortened the next attempt; the budget must now survive
    /// an arbitrarily long run of them intact.
    @Test("A run of misses never starves the budget")
    func missesDoNotStarveTheBudget() {
        let start = Duration.milliseconds(100)
        var timeout = start
        for _ in 0 ..< 32 {
            timeout = MenuBarItemManager.nextMoveOperationTimeout(
                after: timeout, outcome: .displacedWithoutLanding
            )
        }
        #expect(timeout == start)
    }

    /// The decay still compounds across genuinely successful moves, so a
    /// cooperative item is not permanently charged its first slow attempt.
    @Test("The budget still decays across repeated successful moves")
    func successCompounds() {
        var timeout = Duration.milliseconds(256)
        for _ in 0 ..< 3 {
            timeout = MenuBarItemManager.nextMoveOperationTimeout(
                after: timeout, outcome: .landed
            )
        }
        #expect(timeout == .milliseconds(108)) // 256 → 192 → 144 → 108
    }
}
