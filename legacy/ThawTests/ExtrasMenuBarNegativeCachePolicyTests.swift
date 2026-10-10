//
//  ExtrasMenuBarNegativeCachePolicyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Pins the extras-menu-bar negative-cache TTL ladder.
///
/// Cache cleanup follows `NSWorkspace.runningApplications`, which changes
/// whenever any process starts or exits, so clearing the "no extras menu bar"
/// flag there re-probed every app over AX (#956). Deadlines survive cleanup;
/// the ladder keeps late-registered status items findable.
struct ExtrasMenuBarNegativeCachePolicyTests {
    @Test func firstMissRetriesQuickly() {
        // An app that has just launched may publish its status item a
        // moment after it becomes reachable over accessibility.
        #expect(ExtrasMenuBarNegativeCachePolicy.ttl(afterConsecutiveMisses: 1) == .seconds(5))
    }

    @Test func repeatMissesBackOff() {
        #expect(ExtrasMenuBarNegativeCachePolicy.ttl(afterConsecutiveMisses: 2) == .seconds(30))
        #expect(ExtrasMenuBarNegativeCachePolicy.ttl(afterConsecutiveMisses: 3) == .seconds(120))
    }

    @Test func settledAppsReachSteadyStateAndStayThere() {
        for misses in 4...50 {
            #expect(ExtrasMenuBarNegativeCachePolicy.ttl(afterConsecutiveMisses: misses) == .seconds(300))
        }
    }

    @Test func ladderIsMonotonicNondecreasing() {
        var previous = ExtrasMenuBarNegativeCachePolicy.ttl(afterConsecutiveMisses: 1)
        for misses in 2...10 {
            let current = ExtrasMenuBarNegativeCachePolicy.ttl(afterConsecutiveMisses: misses)
            #expect(current >= previous)
            previous = current
        }
    }

    @Test func nonPositiveCountsClampToFirstRung() {
        // A bookkeeping error upstream must degrade to more scanning,
        // never to a longer bar.
        #expect(ExtrasMenuBarNegativeCachePolicy.ttl(afterConsecutiveMisses: 0) == .seconds(5))
        #expect(ExtrasMenuBarNegativeCachePolicy.ttl(afterConsecutiveMisses: -3) == .seconds(5))
    }

    @Test func steadyStateIsBoundedSoLateStatusItemsAreStillFound() {
        // The steady-state rung is the worst-case delay for finding a status
        // item registered long after launch, so it must stay bounded.
        let steadyState = ExtrasMenuBarNegativeCachePolicy.ttl(afterConsecutiveMisses: 99)
        #expect(steadyState <= .seconds(300))
    }

    @Test func earlyRungsCoverTheStartupSettlingWindow() {
        // At login an app can be reachable over AX before it publishes its
        // status item. The first two rungs must elapse inside the ~90s
        // startup settling window.
        let firstTwo = ExtrasMenuBarNegativeCachePolicy.ttl(afterConsecutiveMisses: 1)
            + ExtrasMenuBarNegativeCachePolicy.ttl(afterConsecutiveMisses: 2)
        #expect(firstTwo < .seconds(90))
    }
}
