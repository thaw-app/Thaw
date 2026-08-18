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

    // MARK: Merging with the cached budget

    /// The #687 fix. Smoothing an escalation against the standing value
    /// halved it, so a budget that `nextMoveOperationTimeout` had just raised
    /// by half only rose by a quarter.
    @Test("An escalation is adopted at full size")
    func escalationIsAdoptedWhole() {
        #expect(
            MenuBarItemManager.mergedMoveOperationTimeout(
                proposed: .milliseconds(150), current: .milliseconds(100)
            ) == .milliseconds(150)
        )
    }

    /// Decay stays smoothed: one fast answer should not commit an owner to a
    /// budget it cannot meet again.
    @Test("A decay is smoothed against the standing budget")
    func decayIsSmoothed() {
        #expect(
            MenuBarItemManager.mergedMoveOperationTimeout(
                proposed: .milliseconds(150), current: .milliseconds(250)
            ) == .milliseconds(200)
        )
    }

    /// Regression lock for the #687 ladder. Escalating by half from the old
    /// 100ms default, the log reached only 476ms in eight attempts before
    /// giving up on 1Password. Unsmoothed, four attempts exhaust the budget.
    @Test("Escalation reaches the ceiling in four attempts, not eight")
    func escalationReachesTheCeilingQuickly() {
        var timeout = Duration.milliseconds(250)
        var attempts = 0
        while timeout < .seconds(1) {
            timeout = MenuBarItemManager.mergedMoveOperationTimeout(
                proposed: MenuBarItemManager.nextMoveOperationTimeout(
                    after: timeout, outcome: .ownerDidNotRespond
                ),
                current: timeout
            )
            attempts += 1
        }
        #expect(attempts == 4) // 250 → 375 → 562.5 → 843.75 → 1000
        #expect(timeout == .seconds(1))
    }

    /// An owner that is answering slowly is given up to a second. Past that
    /// it is better classified as unresponsive than as slow.
    @Test("The budget is capped at a second")
    func budgetIsCappedAtASecond() {
        #expect(
            MenuBarItemManager.mergedMoveOperationTimeout(
                proposed: .seconds(4), current: .milliseconds(900)
            ) == .seconds(1)
        )
    }

    /// A budget under 75ms leaves less than eight polls of margin, which is
    /// how the `itemResponseTimeout` cascades started.
    @Test("The budget never falls below the polling floor")
    func budgetNeverFallsBelowTheFloor() {
        #expect(
            MenuBarItemManager.mergedMoveOperationTimeout(
                proposed: .milliseconds(10), current: .milliseconds(20)
            ) == .milliseconds(75)
        )
    }

    /// A cooperative item's budget still walks down over repeated landings
    /// rather than sticking at whatever its first slow attempt cost.
    @Test("Repeated landings still walk the cached budget down")
    func landingsWalkTheBudgetDown() {
        var timeout = Duration.milliseconds(350)
        for _ in 0 ..< 8 {
            timeout = MenuBarItemManager.mergedMoveOperationTimeout(
                proposed: MenuBarItemManager.nextMoveOperationTimeout(
                    after: timeout, outcome: .landed
                ),
                current: timeout
            )
        }
        #expect(timeout < .milliseconds(200))
        #expect(timeout >= .milliseconds(75))
    }
}
