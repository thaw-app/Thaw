//
//  SignatureStabilityGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("A changed item signature has to hold for the grace before it recaches")
struct SignatureStabilityGateTests {
    private let start = ContinuousClock.now
    private let grace = Duration.seconds(3)
    private let cached = ["a", "b"]
    private let changed = ["a", "b", "c"]

    @Test("The first sighting of a difference starts the clock and does not recache")
    func firstSightingStartsTheClock() {
        var gate = SignatureStabilityGate()

        let recache = gate.shouldRecache(cached: cached, current: changed, now: start, grace: grace)

        #expect(!recache)
        #expect(gate.isPending)
        #expect(gate.candidate == changed)
        #expect(gate.firstSeen == start)
    }

    @Test("The same difference inside the grace keeps waiting from the first sighting")
    func sameDifferenceInsideTheGraceKeepsWaiting() {
        var gate = SignatureStabilityGate()
        _ = gate.shouldRecache(cached: cached, current: changed, now: start, grace: grace)

        let recache = gate.shouldRecache(cached: cached, current: changed, now: start + .seconds(2), grace: grace)

        #expect(!recache)
        #expect(gate.candidate == changed)
        #expect(gate.firstSeen == start)
    }

    @Test("The same difference past the grace recaches and clears the gate")
    func sameDifferencePastTheGraceRecaches() {
        var gate = SignatureStabilityGate()
        _ = gate.shouldRecache(cached: cached, current: changed, now: start, grace: grace)

        let recache = gate.shouldRecache(cached: cached, current: changed, now: start + grace, grace: grace)

        #expect(recache)
        #expect(!gate.isPending)
        #expect(gate.firstSeen == nil)
    }

    @Test("A difference that changes restarts the clock")
    func changedDifferenceRestartsTheClock() {
        var gate = SignatureStabilityGate()
        let other = ["a"]
        _ = gate.shouldRecache(cached: cached, current: changed, now: start, grace: grace)

        let restarted = gate.shouldRecache(cached: cached, current: other, now: start + .seconds(2), grace: grace)
        #expect(!restarted)
        #expect(gate.candidate == other)
        #expect(gate.firstSeen == start + .seconds(2))

        // Past the grace measured from the first difference, but not from the second.
        let early = gate.shouldRecache(cached: cached, current: other, now: start + .seconds(4), grace: grace)
        #expect(!early)

        let confirmed = gate.shouldRecache(cached: cached, current: other, now: start + .seconds(5), grace: grace)
        #expect(confirmed)
    }

    @Test("A signature that matches the cache again clears the gate")
    func matchClearsTheGate() {
        var gate = SignatureStabilityGate()
        _ = gate.shouldRecache(cached: cached, current: changed, now: start, grace: grace)

        let recache = gate.shouldRecache(cached: cached, current: cached, now: start + .seconds(10), grace: grace)

        #expect(!recache)
        #expect(!gate.isPending)
        #expect(gate.firstSeen == nil)
    }

    @Test("A flap back to the cache means the difference starts over when it returns")
    func flapStartsOver() {
        var gate = SignatureStabilityGate()
        _ = gate.shouldRecache(cached: cached, current: changed, now: start, grace: grace)
        _ = gate.shouldRecache(cached: cached, current: cached, now: start + .seconds(1), grace: grace)

        let recache = gate.shouldRecache(cached: cached, current: changed, now: start + .seconds(4), grace: grace)

        #expect(!recache)
        #expect(gate.firstSeen == start + .seconds(4))
    }
}
