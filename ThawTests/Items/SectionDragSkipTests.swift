//
//  SectionDragSkipTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Section drag skip")
struct SectionDragSkipTests {
    private typealias Inputs = SectionDragSkip.Inputs

    private static func skip(_ reason: SectionDragSkip.Reason, endsMoveLoop: Bool) -> SectionDragSkip {
        SectionDragSkip(reason: reason, endsMoveLoop: endsMoveLoop)
    }

    // MARK: Each check alone

    @Test("A move that trips nothing goes ahead")
    func nothingFires() {
        #expect(SectionDragSkip.firstReason(for: Inputs()) == nil)
        #expect(SectionDragSkip.firstReason(for: Inputs(isUserInitiated: true, usesPlan: true)) == nil)
    }

    @Test("A parked item defers the order and ends the loop, plan or not")
    func parked() {
        for usesPlan in [false, true] {
            #expect(
                SectionDragSkip.firstReason(for: Inputs(isParked: true, usesPlan: usesPlan))
                    == Self.skip(.parked, endsMoveLoop: true)
            )
        }
    }

    @Test("A tripped breaker suppresses an automatic pass and ends the loop only without a plan")
    func circuitBreaker() {
        #expect(
            SectionDragSkip.firstReason(for: Inputs(breakerTripped: true))
                == Self.skip(.circuitBreaker, endsMoveLoop: true)
        )
        #expect(
            SectionDragSkip.firstReason(for: Inputs(breakerTripped: true, usesPlan: true))
                == Self.skip(.circuitBreaker, endsMoveLoop: false)
        )
    }

    @Test("A user pass is exempt from the breaker")
    func userPassExemptFromBreaker() {
        #expect(SectionDragSkip.firstReason(for: Inputs(isUserInitiated: true, breakerTripped: true)) == nil)
    }

    @Test("A hiding-unsupported item is skipped, and only a planless pass ends the loop")
    func hidingUnsupported() {
        #expect(
            SectionDragSkip.firstReason(for: Inputs(hidingUnsupported: true))
                == Self.skip(.hidingUnsupported, endsMoveLoop: true)
        )
        #expect(
            SectionDragSkip.firstReason(for: Inputs(hidingUnsupported: true, usesPlan: true))
                == Self.skip(.hidingUnsupported, endsMoveLoop: false)
        )
    }

    @Test("A user pass is not exempt from the hiding-unsupported check")
    func userPassStillHitsHidingUnsupported() {
        #expect(
            SectionDragSkip.firstReason(for: Inputs(isUserInitiated: true, hidingUnsupported: true))?.reason
                == .hidingUnsupported
        )
    }

    @Test("An agent-owned item is skipped, and only a planless pass ends the loop")
    func agentOwned() {
        #expect(
            SectionDragSkip.firstReason(for: Inputs(agentOwned: true))
                == Self.skip(.agentOwned, endsMoveLoop: true)
        )
        #expect(
            SectionDragSkip.firstReason(for: Inputs(agentOwned: true, usesPlan: true))
                == Self.skip(.agentOwned, endsMoveLoop: false)
        )
    }

    @Test("A move inside the backoff window is skipped, and only a planless pass ends the loop")
    func recentlyFailed() {
        #expect(
            SectionDragSkip.firstReason(for: Inputs(backingOff: true))
                == Self.skip(.recentlyFailed, endsMoveLoop: true)
        )
        #expect(
            SectionDragSkip.firstReason(for: Inputs(backingOff: true, usesPlan: true))
                == Self.skip(.recentlyFailed, endsMoveLoop: false)
        )
    }

    @Test("A user pass is not exempt from the backoff")
    func userPassStillBacksOff() {
        #expect(
            SectionDragSkip.firstReason(for: Inputs(isUserInitiated: true, backingOff: true))?.reason
                == .recentlyFailed
        )
    }

    // MARK: Order

    @Test("When several checks fire the earliest in the list wins")
    func earliestWins() {
        // Each step turns on one more check, from the last in the order to the first.
        var inputs = Inputs(backingOff: true)
        #expect(SectionDragSkip.firstReason(for: inputs)?.reason == .recentlyFailed)
        inputs.agentOwned = true
        #expect(SectionDragSkip.firstReason(for: inputs)?.reason == .agentOwned)
        inputs.hidingUnsupported = true
        #expect(SectionDragSkip.firstReason(for: inputs)?.reason == .hidingUnsupported)
        inputs.breakerTripped = true
        #expect(SectionDragSkip.firstReason(for: inputs)?.reason == .circuitBreaker)
        inputs.isParked = true
        #expect(SectionDragSkip.firstReason(for: inputs)?.reason == .parked)
    }

    @Test("The breaker's exemption lets the next check in the order answer")
    func exemptBreakerFallsThrough() {
        let inputs = Inputs(
            isUserInitiated: true, breakerTripped: true, hidingUnsupported: true, agentOwned: true, backingOff: true
        )
        #expect(SectionDragSkip.firstReason(for: inputs)?.reason == .hidingUnsupported)
    }

    @Test("The loop-ending flag follows the winning check, not the later ones")
    func endsMoveLoopFollowsWinner() {
        // A parked item ends the loop even on a plan pass where every later check would not.
        let inputs = Inputs(
            isParked: true, breakerTripped: true, hidingUnsupported: true, agentOwned: true, backingOff: true,
            usesPlan: true
        )
        #expect(SectionDragSkip.firstReason(for: inputs) == Self.skip(.parked, endsMoveLoop: true))
    }
}
