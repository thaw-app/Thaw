//
//  ParkedLaneDeficitTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Parked lane deficit")
struct ParkedLaneDeficitTests {
    // Field fixture: four Visible items parked at x == -1 despite 924 pt modeled capacity for 324 pt of items.
    // A 320 pt per-item cap cannot absorb that modeled headroom.
    @Test("Parked items withhold the whole modeled headroom plus their own width")
    func absorbsHeadroom() throws {
        let deficit = try #require(OverflowDeficits.parkedLaneDeficit(
            carried: 0,
            parkedWidths: [32, 38, 38, 41],
            isNativeOverflowActive: true,
            modeledHeadroom: 600
        ))
        let expected: CGFloat = 600 + 149 + 4 * 8
        #expect(deficit == expected)
    }

    /// Field fixture: macOS left five Visible items off a notched bar the model already saw as 228 pt over.
    @Test("When the model already sees the bar as too full, parked items withhold only their width past that")
    func countsNegativeHeadroom() throws {
        let parked: [CGFloat] = [32, 38, 38, 41, 25]
        let parkedWidth: CGFloat = 174 + 5 * 8
        let deficit = try #require(OverflowDeficits.parkedLaneDeficit(
            carried: 0,
            parkedWidths: parked,
            isNativeOverflowActive: true,
            modeledHeadroom: -150
        ))
        #expect(deficit == parkedWidth - 150)

        #expect(OverflowDeficits.parkedLaneDeficit(
            carried: 0,
            parkedWidths: parked,
            isNativeOverflowActive: true,
            modeledHeadroom: -228
        ) == nil, "the model already conceals more than macOS left off")
    }

    @Test("Once the parked items are concealed the deficit carries, so they stay out")
    func carriesAfterConcealing() throws {
        let held = try #require(OverflowDeficits.parkedLaneDeficit(
            carried: 781,
            parkedWidths: [],
            isNativeOverflowActive: true,
            modeledHeadroom: 900
        ))
        #expect(held == 781)
    }

    @Test("Parked items without native overflow are not proof of a full bar")
    func ignoresParkedItemsWithoutNativeOverflow() {
        #expect(OverflowDeficits.parkedLaneDeficit(
            carried: 0,
            parkedWidths: [32, 38, 38, 41],
            isNativeOverflowActive: false,
            modeledHeadroom: 600
        ) == nil)
    }

    @Test("A held deficit survives native overflow clearing")
    func carriesWithoutNativeOverflow() throws {
        let held = try #require(OverflowDeficits.parkedLaneDeficit(
            carried: 781,
            parkedWidths: [32],
            isNativeOverflowActive: false,
            modeledHeadroom: 900
        ))
        #expect(held == 781)
    }

    @Test("A collapsed width is charged as a nominal item")
    func collapsedWidthIsNominal() throws {
        let deficit = try #require(OverflowDeficits.parkedLaneDeficit(
            carried: 0,
            parkedWidths: [2],
            isNativeOverflowActive: true,
            modeledHeadroom: 0
        ))
        #expect(deficit == OverflowDeficits.nominalStatusItemWidth + 8)
    }
}
