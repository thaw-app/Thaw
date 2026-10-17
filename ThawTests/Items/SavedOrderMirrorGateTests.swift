//
//  SavedOrderMirrorGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// The live order becomes the saved order only once the bar has been quiet for a while.
@MainActor
@Suite("Saved order mirror gate")
struct SavedOrderMirrorGateTests {
    private let start = ContinuousClock.now
    private let items: Set<String> = ["a", "b", "c"]

    private func at(_ seconds: Double) -> ContinuousClock.Instant {
        start + .milliseconds(Int(seconds * 1000))
    }

    @Test("A quiet bar may be mirrored")
    func quietBarMirrors() {
        let gate = SavedOrderMirrorGate(observesSystem: false)
        #expect(gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(0)))
        #expect(gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(3)))
    }

    @Test("An item arriving holds the mirror past the agent's rewrite 10 s later")
    func arrivalHoldsTheMirror() {
        let gate = SavedOrderMirrorGate(observesSystem: false)
        _ = gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(0))
        #expect(!gate.allowsMirror(identifiers: items.union(["d"]), restrictionChange: nil, now: at(1)))
        #expect(!gate.allowsMirror(identifiers: items.union(["d"]), restrictionChange: nil, now: at(11.5)))
        #expect(gate.allowsMirror(identifiers: items.union(["d"]), restrictionChange: nil, now: at(13.5)))
    }

    @Test("An item leaving holds the mirror too")
    func departureHoldsTheMirror() {
        let gate = SavedOrderMirrorGate(observesSystem: false)
        _ = gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(0))
        #expect(!gate.allowsMirror(identifiers: ["a", "b"], restrictionChange: nil, now: at(1)))
    }

    @Test("One item swapped for another in the same pass holds the mirror")
    func swapHoldsTheMirror() {
        let gate = SavedOrderMirrorGate(observesSystem: false)
        _ = gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(0))
        #expect(!gate.allowsMirror(identifiers: ["a", "b", "d"], restrictionChange: nil, now: at(1)))
    }

    @Test("A recent hiding change holds the mirror")
    func restrictionChangeHoldsTheMirror() {
        let gate = SavedOrderMirrorGate(observesSystem: false)
        #expect(!gate.allowsMirror(identifiers: items, restrictionChange: at(1), now: at(2)))
        #expect(gate.allowsMirror(identifiers: items, restrictionChange: at(1), now: at(14)))
    }

    @Test("A wake or display change holds the mirror")
    func systemEventHoldsTheMirror() {
        let gate = SavedOrderMirrorGate(observesSystem: false)
        _ = gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(0))
        gate.noteDisturbance(at: at(10))
        #expect(!gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(12)))
        #expect(gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(23)))
    }

    @Test("The quiet rule on its own")
    func quietRule() {
        #expect(SavedOrderMirrorGate.isQuiet(now: at(10), events: [nil, at(2)], quietPeriod: .seconds(5)))
        #expect(!SavedOrderMirrorGate.isQuiet(now: at(10), events: [at(2), at(8)], quietPeriod: .seconds(5)))
        #expect(SavedOrderMirrorGate.isQuiet(now: at(10), events: [], quietPeriod: .seconds(5)))
    }
}
