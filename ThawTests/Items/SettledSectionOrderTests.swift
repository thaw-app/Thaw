//
//  SettledSectionOrderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

/// A section apply leaves the position table alone when its members already sit in order on their side.
@Suite("Settled section order")
struct SettledSectionOrderTests {
    // Higher weights sit further left: Always Hidden 1368, Hidden 247, Visible control 113.
    private let dividers = ObservedMembership.Dividers(hidden: 247, alwaysHidden: 1368, visibleControl: 113)!

    @Test(
        "Members on their side of the divider with strictly falling weights are already in order",
        arguments: [
            ([661, 660, 573, 492, 442, 419], MenuBarSectionName.hidden),
            ([3000, 2000, 1500], .alwaysHidden),
        ] as [([Int?], MenuBarSectionName)]
    )
    func settled(weights: [Int?], section: MenuBarSectionName) {
        #expect(SettledSectionOrder.isInOrder(weights, section: section, dividers: dividers))
    }

    /// Tied weights need the write since the agent breaks a tie its own way, and fewer than two
    /// members leave nothing to check.
    @Test(
        "Swapped, tied, unweighed, misplaced or lone members need the write",
        arguments: [
            ([661, 573, 660, 492], MenuBarSectionName.hidden),
            ([661, 661, 573], .hidden),
            ([661, nil, 573], .hidden),
            ([661, 573, 200], .hidden),
            ([2000, 661, 573], .hidden),
            ([3000, 1500, 2000], .alwaysHidden),
            ([661], .hidden),
            ([], .hidden),
        ] as [([Int?], MenuBarSectionName)]
    )
    func needsTheWrite(weights: [Int?], section: MenuBarSectionName) {
        #expect(!SettledSectionOrder.isInOrder(weights, section: section, dividers: dividers))
    }

    @Test("An ascending axis reads the order the other way round")
    func ascendingAxis() {
        let ascending = ObservedMembership.Dividers(hidden: -247, alwaysHidden: -1368, visibleControl: -113)!
        #expect(SettledSectionOrder.isInOrder([-661, -660, -573], section: .hidden, dividers: ascending))
        #expect(!SettledSectionOrder.isInOrder([-573, -660, -661], section: .hidden, dividers: ascending))
    }
}
