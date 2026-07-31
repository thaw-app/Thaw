//
//  SourcePIDNegativeCachePolicyTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import Testing
@testable import Thaw

/// Pins the negative-cache TTL ladder.
///
/// The regression this ladder fixes: the app front-loads its sourcePID
/// resolution requests into its startup settling window (~90s), and the
/// first cold AX scan routinely under-resolves. With a flat 60s TTL, one
/// failed cold scan barred a window past the last request the app would
/// ever make for it, wedging resolution for the whole session. The early
/// rungs must therefore stay comfortably inside the settling window, and
/// the ladder must never bar a window permanently.
struct SourcePIDNegativeCachePolicyTests {
    @Test func firstFailureRetriesQuickly() {
        #expect(SourcePIDNegativeCachePolicy.ttl(afterConsecutiveFailures: 1) == .seconds(5))
    }

    @Test func secondFailureBacksOff() {
        #expect(SourcePIDNegativeCachePolicy.ttl(afterConsecutiveFailures: 2) == .seconds(15))
    }

    @Test func repeatFailuresReachSteadyStateAndStayThere() {
        for failures in 3...20 {
            #expect(SourcePIDNegativeCachePolicy.ttl(afterConsecutiveFailures: failures) == .seconds(60))
        }
    }

    @Test func ladderIsMonotonicNondecreasing() {
        var previous = SourcePIDNegativeCachePolicy.ttl(afterConsecutiveFailures: 1)
        for failures in 2...10 {
            let current = SourcePIDNegativeCachePolicy.ttl(afterConsecutiveFailures: failures)
            #expect(current >= previous)
            previous = current
        }
    }

    @Test func nonPositiveCountsClampToFirstRung() {
        // A bookkeeping error upstream must degrade to more scanning,
        // never to a longer bar.
        #expect(SourcePIDNegativeCachePolicy.ttl(afterConsecutiveFailures: 0) == .seconds(5))
        #expect(SourcePIDNegativeCachePolicy.ttl(afterConsecutiveFailures: -3) == .seconds(5))
    }

    @Test func earlyRungsFitInsideTheSettlingWindow() {
        // First two retries must complete within the app's ~90s settling
        // window with margin: 5 + 15 leaves three scan opportunities
        // before requests stop.
        let firstTwo = SourcePIDNegativeCachePolicy.ttl(afterConsecutiveFailures: 1)
            + SourcePIDNegativeCachePolicy.ttl(afterConsecutiveFailures: 2)
        #expect(firstTwo < .seconds(30))
    }
}
