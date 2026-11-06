//
//  EnvironmentSnapshotTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@MainActor
@Suite("Environment snapshot")
struct EnvironmentSnapshotTests {
    private static let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private static let external = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
    private static let single = DisplayArrangement(frames: [1: builtIn], mainDisplayID: 1)
    private static let docked = DisplayArrangement(frames: [1: builtIn, 2: external], mainDisplayID: 1)

    @Test("A new display is classified as added")
    func displayAdded() {
        #expect(EnvironmentChange(from: Self.single, to: Self.docked) == .displayAdded)
    }

    @Test("A display that goes away is classified as removed")
    func displayRemoved() {
        #expect(EnvironmentChange(from: Self.docked, to: Self.single) == .displayRemoved)
    }

    @Test("A moved display, another main display or a swapped display is a rearrangement")
    func rearranged() {
        let moved = DisplayArrangement(frames: [1: Self.builtIn, 2: Self.external.offsetBy(dx: -4024, dy: 0)], mainDisplayID: 1)
        let otherMain = DisplayArrangement(frames: Self.docked.frames, mainDisplayID: 2)
        let swapped = DisplayArrangement(frames: [1: Self.builtIn, 3: Self.external], mainDisplayID: 1)
        #expect(EnvironmentChange(from: Self.docked, to: moved) == .rearranged)
        #expect(EnvironmentChange(from: Self.docked, to: otherMain) == .rearranged)
        #expect(EnvironmentChange(from: Self.docked, to: swapped) == .rearranged)
    }

    @Test("A new size on the same displays is a resolution change, even when a neighbour shifts")
    func resolutionOnly() {
        let scaled = DisplayArrangement(frames: [1: CGRect(x: 0, y: 0, width: 1800, height: 1169), 2: Self.external.offsetBy(dx: 288, dy: 0)], mainDisplayID: 1)
        #expect(EnvironmentChange(from: Self.docked, to: scaled) == .resolutionOnly)
    }

    @Test("The same displays in the same places are no change")
    func noChange() {
        #expect(EnvironmentChange(from: Self.docked, to: Self.docked) == EnvironmentChange.none)
    }

    @Test("Generation increments once per settled change and not for an unchanged settle")
    func generationCountsChanges() {
        let snapshot = EnvironmentSnapshot(arrangement: Self.single)
        #expect(snapshot.generation == 0)

        #expect(snapshot.settle(on: Self.docked) == .displayAdded)
        #expect(snapshot.generation == 1)
        #expect(snapshot.arrangement == Self.docked)

        #expect(snapshot.settle(on: Self.docked) == EnvironmentChange.none)
        #expect(snapshot.generation == 1)

        #expect(snapshot.settle(on: Self.single) == .displayRemoved)
        #expect(snapshot.generation == 2)
    }

    @Test("Two equal reads settle, and the read cap settles on the last read")
    func settleDecision() {
        let timing = EnvironmentSettle.Timing()
        #expect(!EnvironmentSettle.isSettled(previous: nil, current: Self.docked, reads: 1, timing: timing))
        #expect(!EnvironmentSettle.isSettled(previous: Self.single, current: Self.docked, reads: 2, timing: timing))
        #expect(EnvironmentSettle.isSettled(previous: Self.docked, current: Self.docked, reads: 2, timing: timing))
        #expect(EnvironmentSettle.isSettled(previous: Self.single, current: Self.docked, reads: 6, timing: timing))
    }

    @Test("The first read waits for quiet and later reads wait to confirm")
    func readDelays() {
        let timing = EnvironmentSettle.Timing()
        #expect(EnvironmentSettle.delay(beforeRead: 1, timing: timing) == .milliseconds(300))
        #expect(EnvironmentSettle.delay(beforeRead: 2, timing: timing) == .milliseconds(150))
        #expect(EnvironmentSettle.delay(beforeRead: 6, timing: timing) == .milliseconds(150))
    }
}
