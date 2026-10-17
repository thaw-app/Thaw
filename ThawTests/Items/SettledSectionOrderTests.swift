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

    @Test("Six Hidden items with falling weights are already in order")
    func loggedHiddenOrderIsSettled() {
        #expect(SettledSectionOrder.isInOrder([661, 660, 573, 492, 442, 419], section: .hidden, dividers: dividers))
    }

    @Test("Two members out of order need the write")
    func swappedMembersNeedTheWrite() {
        #expect(!SettledSectionOrder.isInOrder([661, 573, 660, 492], section: .hidden, dividers: dividers))
    }

    @Test("Tied weights need the write, since the agent breaks a tie its own way")
    func tiedWeightsNeedTheWrite() {
        #expect(!SettledSectionOrder.isInOrder([661, 661, 573], section: .hidden, dividers: dividers))
    }

    @Test("A member without a weight needs the write")
    func missingWeightNeedsTheWrite() {
        #expect(!SettledSectionOrder.isInOrder([661, nil, 573], section: .hidden, dividers: dividers))
    }

    @Test("A member across the divider needs the write even in order")
    func memberAcrossDividerNeedsTheWrite() {
        #expect(!SettledSectionOrder.isInOrder([661, 573, 200], section: .hidden, dividers: dividers))
        #expect(!SettledSectionOrder.isInOrder([2000, 661, 573], section: .hidden, dividers: dividers))
    }

    @Test("Always Hidden members beyond their divider and in order are settled")
    func alwaysHiddenSettled() {
        #expect(SettledSectionOrder.isInOrder([3000, 2000, 1500], section: .alwaysHidden, dividers: dividers))
        #expect(!SettledSectionOrder.isInOrder([3000, 1500, 2000], section: .alwaysHidden, dividers: dividers))
    }

    @Test("An ascending axis reads the order the other way round")
    func ascendingAxis() {
        let ascending = ObservedMembership.Dividers(hidden: -247, alwaysHidden: -1368, visibleControl: -113)!
        #expect(SettledSectionOrder.isInOrder([-661, -660, -573], section: .hidden, dividers: ascending))
        #expect(!SettledSectionOrder.isInOrder([-573, -660, -661], section: .hidden, dividers: ascending))
    }

    @Test("Fewer than two members leave nothing to check, so the write goes ahead")
    func singleMemberWrites() {
        #expect(!SettledSectionOrder.isInOrder([661], section: .hidden, dividers: dividers))
        #expect(!SettledSectionOrder.isInOrder([], section: .hidden, dividers: dividers))
    }
}
