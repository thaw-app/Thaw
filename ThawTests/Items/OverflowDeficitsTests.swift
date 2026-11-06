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
@Suite("A withheld overflow width holds while the same items compete, and drops when one arrives or leaves")
struct OverflowDeficitsTests {
    private let nominal = OverflowDeficits.nominalStatusItemWidth

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
        #expect(deficits.parkedLane == nil)
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

    @Test("The parked deficit holds after its items are concealed, and drops when one leaves")
    func parkedDeficitHoldsThenDrops() {
        var deficits = OverflowDeficits()

        let found = deficits.updateParkedLane(
            parkedWidths: [32, 38],
            isNativeOverflowActive: true,
            modeledHeadroom: 100,
            visibleUIDs: ["a", "b", "c"],
            overflowUIDs: []
        )
        let expected: CGFloat = 100 + 32 + 38 + 2 * 8
        #expect(found == .init(width: expected, previousWidth: nil))

        let held = deficits.updateParkedLane(
            parkedWidths: [],
            isNativeOverflowActive: false,
            modeledHeadroom: 900,
            visibleUIDs: ["c"],
            overflowUIDs: ["a", "b"]
        )
        #expect(held == .init(width: expected, previousWidth: expected))
        #expect(!held.changed)

        let dropped = deficits.updateParkedLane(
            parkedWidths: [],
            isNativeOverflowActive: false,
            modeledHeadroom: 900,
            visibleUIDs: ["c"],
            overflowUIDs: ["a"]
        )
        #expect(dropped == .init(width: nil, previousWidth: expected))
        #expect(deficits.parkedLane == nil)
    }

    @Test("The two deficits are held apart")
    func deficitsAreIndependent() {
        var deficits = OverflowDeficits()
        _ = deficits.updateNotchOcclusion(occludedControlWidth: 20, visibleUIDs: ["a", "b"], overflowUIDs: [])

        let parked = deficits.updateParkedLane(
            parkedWidths: [],
            isNativeOverflowActive: true,
            modeledHeadroom: 500,
            visibleUIDs: ["a", "b"],
            overflowUIDs: []
        )

        #expect(parked == .init(width: nil, previousWidth: nil))
        #expect(deficits.notchOcclusion?.width == 20 + nominal)
        #expect(deficits.parkedLane == nil)
    }
}
