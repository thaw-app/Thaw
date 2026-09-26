//
//  MoveOperationTimeoutTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// How a move attempt's outcome sizes the next attempt's budget.
///
/// `postMoveEvents` waits for the origin to change, not for arrival, so a miss
/// still nudges the item a pixel or two. Treating that as a fast response let a
/// run of misses starve the budget into an `itemResponseTimeout` cascade (#881).
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

    /// An unresponsive owner earns a longer budget.
    @Test("An unresponsive owner grows the budget by half")
    func unresponsiveOwnerGrowsTheBudget() {
        #expect(
            MenuBarItemManager.nextMoveOperationTimeout(
                after: .milliseconds(100), outcome: .ownerDidNotRespond
            ) == .milliseconds(150)
        )
    }

    /// A miss is neutral: no evidence the owner is keeping up or has stopped answering.
    @Test("Displacing the item without landing it leaves the budget alone")
    func missIsNeutral() {
        #expect(
            MenuBarItemManager.nextMoveOperationTimeout(
                after: .milliseconds(100), outcome: .displacedWithoutLanding
            ) == .milliseconds(100)
        )
    }

    /// UserSwitcher drifted 1144 to 1137 over three misses, then timed out (#881).
    /// The budget must survive any run of misses intact.
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

    /// Decay still compounds across real successes, so a cooperative item is not
    /// charged its first slow attempt forever.
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

    /// Smoothing an escalation against the standing value halved it, so a
    /// budget raised by half only rose by a quarter (#687).
    @Test("An escalation is adopted at full size")
    func escalationIsAdoptedWhole() {
        #expect(
            MenuBarItemManager.mergedMoveOperationTimeout(
                proposed: .milliseconds(150), current: .milliseconds(100)
            ) == .milliseconds(150)
        )
    }

    /// Decay stays smoothed: one fast answer should not commit an owner to a budget it cannot meet again.
    @Test("A decay is smoothed against the standing budget")
    func decayIsSmoothed() {
        #expect(
            MenuBarItemManager.mergedMoveOperationTimeout(
                proposed: .milliseconds(150), current: .milliseconds(250)
            ) == .milliseconds(200)
        )
    }

    /// Escalating by half from 100ms reached only 476ms in eight attempts before
    /// giving up on 1Password (#687). Unsmoothed, four attempts exhaust the budget.
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

    /// Past a second, a slow owner is better classified as unresponsive.
    @Test("The budget is capped at a second")
    func budgetIsCappedAtASecond() {
        #expect(
            MenuBarItemManager.mergedMoveOperationTimeout(
                proposed: .seconds(4), current: .milliseconds(900)
            ) == .seconds(1)
        )
    }

    /// Under 75ms leaves less than eight polls of margin, which started the `itemResponseTimeout` cascades.
    @Test("The budget never falls below the polling floor")
    func budgetNeverFallsBelowTheFloor() {
        #expect(
            MenuBarItemManager.mergedMoveOperationTimeout(
                proposed: .milliseconds(10), current: .milliseconds(20)
            ) == .milliseconds(75)
        )
    }

    /// A cooperative item's budget walks down over repeated landings instead of sticking at its first slow cost.
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

/// The cursor-hide watchdog must outlast the worst single `move`: each attempt
/// spends its budget four times (two posts, two waits), budgets escalate to the
/// ceiling, and a failure posts one 100 ms fallback. Outlasting the watchdog
/// force-shows the cursor mid-sequence, the flash this sizing prevents.
@Suite("Cursor hide watchdog sizing")
struct CursorHideWatchdogSizingTests {
    @Test("The default ceiling sizes the watchdog past eight escalated attempts")
    func defaultCeilingCoversWorstCase() {
        let watchdog = MenuBarItemManager.cursorHideWatchdogTimeout()
        // 4 operations × 1 s × 8 attempts + 100 ms fallback.
        #expect(watchdog == .milliseconds(32_100))
    }

    @Test("Ordinary budgets keep the historical 10 s floor")
    func ordinaryBudgetsKeepTheFloor() {
        // A never-escalated item: 4 × 250 ms × 8 + 100 ms = 8.1 s, below the floor.
        let watchdog = MenuBarItemManager.cursorHideWatchdogTimeout(
            operationCeiling: .milliseconds(250)
        )
        #expect(watchdog == .seconds(10))
    }

    @Test("Attempt count and fallback scale the result")
    func attemptCountAndFallbackScale() {
        // Above the floor: 4 × 1 s × 3 attempts + 500 ms = 12.5 s.
        #expect(MenuBarItemManager.cursorHideWatchdogTimeout(
            operationCeiling: .seconds(1),
            maxAttempts: 3,
            fallbackPost: .milliseconds(500)
        ) == .milliseconds(12_500))
    }
}
