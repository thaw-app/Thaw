//
//  SourcePIDNegativeCachePolicyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import Testing
@testable import Thaw

/// Pins the negative-cache TTL ladder.
///
/// With a flat 60s TTL, one failed cold AX scan during the ~90s startup
/// settling window barred a window past the app's last request for it,
/// wedging resolution for the session. Early rungs must stay inside the
/// settling window, and the ladder must never bar a window permanently.
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
