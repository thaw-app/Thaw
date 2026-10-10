//
//  ParkedLaneDeficitTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Parked lane deficit")
struct ParkedLaneDeficitTests {
    // Field fixture: four Visible items parked at x == -1 despite 924 pt modeled capacity for 324 pt of items.
    // A 320 pt per-item cap cannot absorb that modeled headroom.
    private let visible: Set<String> = ["spark", "antishort", "cider", "slidepad", "walld", "mole"]

    @Test("Parked items withhold the whole modeled headroom plus their own width")
    func absorbsHeadroom() throws {
        let deficit = try #require(MenuBarItemManager.parkedLaneDeficit(
            previous: nil,
            parkedWidths: [32, 38, 38, 41],
            isNativeOverflowActive: true,
            modeledHeadroom: 600,
            visibleUIDs: visible,
            overflowUIDs: []
        ))
        let expected: CGFloat = 600 + 149 + 4 * 8
        #expect(deficit.width == expected)
    }

    @Test("Once the parked items are concealed the deficit carries, so they stay out")
    func carriesAfterConcealing() throws {
        let previous = (width: CGFloat(781), visibleUIDs: visible)
        let held = try #require(MenuBarItemManager.parkedLaneDeficit(
            previous: previous,
            parkedWidths: [],
            isNativeOverflowActive: true,
            modeledHeadroom: 900,
            visibleUIDs: ["walld", "mole"],
            overflowUIDs: ["spark", "antishort", "cider", "slidepad"]
        ))
        #expect(held.width == 781)
    }

    @Test("Parked items without native overflow are not proof of a full bar")
    func ignoresParkedItemsWithoutNativeOverflow() {
        #expect(MenuBarItemManager.parkedLaneDeficit(
            previous: nil,
            parkedWidths: [32, 38, 38, 41],
            isNativeOverflowActive: false,
            modeledHeadroom: 600,
            visibleUIDs: visible,
            overflowUIDs: []
        ) == nil)
    }

    @Test("A held deficit survives native overflow clearing")
    func carriesWithoutNativeOverflow() throws {
        let previous = (width: CGFloat(781), visibleUIDs: visible)
        let held = try #require(MenuBarItemManager.parkedLaneDeficit(
            previous: previous,
            parkedWidths: [32],
            isNativeOverflowActive: false,
            modeledHeadroom: 900,
            visibleUIDs: visible,
            overflowUIDs: []
        ))
        #expect(held.width == 781)
    }

    @Test("A collapsed width is charged as a nominal item")
    func collapsedWidthIsNominal() throws {
        let deficit = try #require(MenuBarItemManager.parkedLaneDeficit(
            previous: nil,
            parkedWidths: [2],
            isNativeOverflowActive: true,
            modeledHeadroom: 0,
            visibleUIDs: ["a"],
            overflowUIDs: []
        ))
        #expect(deficit.width == MenuBarItemManager.nominalStatusItemWidth + 8)
    }

    @Test("An item arriving or leaving drops the deficit")
    func dropsOnMembershipChange() {
        let previous = (width: CGFloat(80), visibleUIDs: Set(["a", "b", "c"]))
        #expect(MenuBarItemManager.parkedLaneDeficit(
            previous: previous,
            parkedWidths: [],
            isNativeOverflowActive: true,
            modeledHeadroom: 500,
            visibleUIDs: ["a", "b"],
            overflowUIDs: []
        ) == nil)
    }
}
