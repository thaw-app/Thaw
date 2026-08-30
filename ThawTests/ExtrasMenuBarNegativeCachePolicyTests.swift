//
//  ExtrasMenuBarNegativeCachePolicyTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Pins the extras-menu-bar negative-cache TTL ladder.
///
/// The regression this ladder fixes: the per-app "checked, no extras menu
/// bar" flag was cleared on every cache cleanup, and cleanup is driven by
/// `NSWorkspace.runningApplications` — which changes whenever any process on
/// the system starts or exits. A field log (#956) showed cleanup running 46
/// times in seven minutes, so nearly every full scan re-probed all ~170
/// running applications over the Accessibility API even though only ~16 of
/// them have an extras menu bar at all. Deadlines make the skip survive
/// cleanup; the ladder is what keeps late-registered status items findable.
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
        // An app that registers a status item long after launch has to be
        // rediscovered without user action. The steady-state rung is the
        // worst-case delay for that, so it must stay bounded — this is the
        // property the deleted blanket reset used to provide.
        let steadyState = ExtrasMenuBarNegativeCachePolicy.ttl(afterConsecutiveMisses: 99)
        #expect(steadyState <= .seconds(300))
    }

    @Test func earlyRungsCoverTheStartupSettlingWindow() {
        // Logging in launches every status-item agent at once, and an app
        // that is reachable over accessibility before it publishes its
        // status item comes back empty on the first probe. The first two
        // rungs must therefore both elapse inside the app's ~90s startup
        // settling window, giving such an app three chances to be seen
        // before the ladder backs off to minutes.
        let firstTwo = ExtrasMenuBarNegativeCachePolicy.ttl(afterConsecutiveMisses: 1)
            + ExtrasMenuBarNegativeCachePolicy.ttl(afterConsecutiveMisses: 2)
        #expect(firstTwo < .seconds(90))
    }
}
