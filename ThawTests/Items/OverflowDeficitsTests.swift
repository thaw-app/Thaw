//
//  OverflowDeficitsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("A notch deficit drops when an item arrives or leaves; a learned shortfall stays with its display")
struct OverflowDeficitsTests {
    private let nominal = OverflowDeficits.nominalStatusItemWidth

    // A notched 14-inch built-in display.
    private let builtIn = OverflowDeficits.Display(id: 1, width: 1512)

    @Test("A held width carries whole while membership is unchanged")
    func carriesWhileMembershipIsUnchanged() {
        let held = (width: CGFloat(44), visibleUIDs: Set(["a", "b", "c"]))

        #expect(OverflowDeficits.carriedWidth(from: held, membership: ["a", "b", "c"]) == 44)
    }

    @Test("A held width carries nothing once an item arrived or left")
    func carriesNothingAfterMembershipChange() {
        let held = (width: CGFloat(44), visibleUIDs: Set(["a", "b", "c"]))

        #expect(OverflowDeficits.carriedWidth(from: held, membership: ["a", "b"]) == 0)
        #expect(OverflowDeficits.carriedWidth(from: held, membership: ["a", "b", "c", "d"]) == 0)
        #expect(OverflowDeficits.carriedWidth(from: nil, membership: ["a", "b", "c"]) == 0)
    }

    @Test("Nothing is withheld to begin with, and a pass that finds nothing reports no change")
    func startsEmpty() {
        var deficits = OverflowDeficits()

        let update = deficits.updateNotchOcclusion(occludedControlWidth: 0, visibleUIDs: ["a"], overflowUIDs: [])

        #expect(update == .init(width: nil, previousWidth: nil))
        #expect(!update.changed)
        #expect(deficits.notchOcclusion == nil)
        #expect(deficits.parkedLanes.isEmpty)
    }

    @Test("The notch deficit grows while covered, then holds once the concealed item moved to overflow")
    func notchDeficitGrowsThenHolds() {
        var deficits = OverflowDeficits()

        let first = deficits.updateNotchOcclusion(occludedControlWidth: 20, visibleUIDs: ["a", "b", "c"], overflowUIDs: [])
        #expect(first == .init(width: 20 + nominal, previousWidth: nil))
        #expect(first.changed)

        let second = deficits.updateNotchOcclusion(occludedControlWidth: 20, visibleUIDs: ["a", "b"], overflowUIDs: ["c"])
        #expect(second == .init(width: 2 * (20 + nominal), previousWidth: 20 + nominal))
        #expect(second.changed)

        let third = deficits.updateNotchOcclusion(occludedControlWidth: 0, visibleUIDs: ["a", "b"], overflowUIDs: ["c"])
        #expect(third == .init(width: 2 * (20 + nominal), previousWidth: 2 * (20 + nominal)))
        #expect(!third.changed)
        #expect(deficits.notchOcclusion?.visibleUIDs == ["a", "b", "c"])
    }

    @Test("An item leaving drops the held notch deficit, and the pass reports what it was")
    func notchDeficitDropsWhenAnItemLeaves() {
        var deficits = OverflowDeficits()
        _ = deficits.updateNotchOcclusion(occludedControlWidth: 20, visibleUIDs: ["a", "b", "c"], overflowUIDs: [])

        let update = deficits.updateNotchOcclusion(occludedControlWidth: 0, visibleUIDs: ["a", "b"], overflowUIDs: [])

        #expect(update == .init(width: nil, previousWidth: 20 + nominal))
        #expect(update.changed)
        #expect(deficits.notchOcclusion == nil)
    }

    @Test("An item arriving restarts a still-covered notch deficit from nothing")
    func notchDeficitRestartsWhenAnItemArrives() {
        var deficits = OverflowDeficits()
        _ = deficits.updateNotchOcclusion(occludedControlWidth: 20, visibleUIDs: ["a", "b"], overflowUIDs: [])
        _ = deficits.updateNotchOcclusion(occludedControlWidth: 20, visibleUIDs: ["a"], overflowUIDs: ["b"])

        let update = deficits.updateNotchOcclusion(occludedControlWidth: 20, visibleUIDs: ["a", "d"], overflowUIDs: ["b"])

        #expect(update == .init(width: 20 + nominal, previousWidth: 2 * (20 + nominal)))
        #expect(deficits.notchOcclusion?.visibleUIDs == ["a", "b", "d"])
    }

    @Test("The parked deficit holds after its items are concealed")
    func parkedDeficitHoldsAfterConcealing() {
        var deficits = OverflowDeficits()

        let found = deficits.updateParkedLane(
            parkedWidths: [32, 38],
            isNativeOverflowActive: true,
            modeledHeadroom: 100,
            display: builtIn
        )
        let expected: CGFloat = 100 + 32 + 38 + 2 * 8
        #expect(found == .init(width: expected, previousWidth: nil))

        let held = deficits.updateParkedLane(
            parkedWidths: [],
            isNativeOverflowActive: false,
            modeledHeadroom: 900,
            display: builtIn
        )
        #expect(held == .init(width: expected, previousWidth: expected))
        #expect(!held.changed)
    }

    /// macOS left two of 16 Visible items (29.5 pt each, 75 pt with gaps) off a bar the model
    /// gave 54.5 pt of headroom: 630.5 pt of room for 576 pt of items.
    private func learnShortfall(_ deficits: inout OverflowDeficits) {
        _ = deficits.updateParkedLane(
            parkedWidths: [29.5, 29.5],
            isNativeOverflowActive: true,
            modeledHeadroom: 54.5,
            display: builtIn
        )
    }

    @Test("A learned shortfall survives an item leaving Visible")
    func shortfallSurvivesAnItemLeaving() {
        var deficits = OverflowDeficits()
        learnShortfall(&deficits)

        // One app moved to Hidden: 637.5 pt of room for the remaining 536 pt of items.
        let update = deficits.updateParkedLane(
            parkedWidths: [],
            isNativeOverflowActive: false,
            modeledHeadroom: 101.5,
            display: builtIn
        )

        #expect(update == .init(width: 129.5, previousWidth: 129.5))
    }

    @Test("A learned shortfall survives an item arriving in Visible")
    func shortfallSurvivesAnItemArriving() {
        var deficits = OverflowDeficits()
        learnShortfall(&deficits)

        // A 30 pt app arrived: 630.5 pt of room for 606 pt of items.
        let update = deficits.updateParkedLane(
            parkedWidths: [],
            isNativeOverflowActive: false,
            modeledHeadroom: 24.5,
            display: builtIn
        )

        #expect(update == .init(width: 129.5, previousWidth: 129.5))
    }

    @Test("A learned shortfall is dropped when its display changes width")
    func shortfallDropsWhenTheDisplayWidthChanges() {
        var deficits = OverflowDeficits()
        learnShortfall(&deficits)

        let update = deficits.updateParkedLane(
            parkedWidths: [],
            isNativeOverflowActive: false,
            modeledHeadroom: 101.5,
            display: .init(id: 1, width: 1800)
        )

        #expect(update == .init(width: nil, previousWidth: 129.5))
    }

    @Test("A shortfall learned on one display is not withheld on another")
    func shortfallIsNotWithheldOnAnotherDisplay() {
        var deficits = OverflowDeficits()
        learnShortfall(&deficits)

        let update = deficits.updateParkedLane(
            parkedWidths: [],
            isNativeOverflowActive: false,
            modeledHeadroom: 1200,
            display: .init(id: 2, width: 1512)
        )

        #expect(update.width == nil)
    }

    @Test("Each display keeps its own shortfall while the menu bar moves between them")
    func shortfallIsKeptPerDisplay() {
        var deficits = OverflowDeficits()
        learnShortfall(&deficits)
        _ = deficits.updateParkedLane(
            parkedWidths: [],
            isNativeOverflowActive: false,
            modeledHeadroom: 1200,
            display: .init(id: 2, width: 2560)
        )

        let update = deficits.updateParkedLane(
            parkedWidths: [],
            isNativeOverflowActive: false,
            modeledHeadroom: 54.5,
            display: builtIn
        )

        #expect(update.width == 129.5)
    }

    @Test("The two deficits are held apart")
    func deficitsAreIndependent() {
        var deficits = OverflowDeficits()
        _ = deficits.updateNotchOcclusion(occludedControlWidth: 20, visibleUIDs: ["a", "b"], overflowUIDs: [])

        let parked = deficits.updateParkedLane(
            parkedWidths: [],
            isNativeOverflowActive: true,
            modeledHeadroom: 500,
            display: builtIn
        )

        #expect(parked == .init(width: nil, previousWidth: nil))
        #expect(deficits.notchOcclusion?.width == 20 + nominal)
        #expect(deficits.parkedLanes.isEmpty)
    }
}
