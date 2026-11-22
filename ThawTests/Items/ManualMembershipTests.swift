//
//  ManualMembershipTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Manual membership from weights")
struct ManualMembershipTests {
    // Weights from a real table, where a higher weight sits further left:
    // Always Hidden 1368, Hidden 328, Visible control 161.
    @Test(arguments: [
        (2000, MenuBarSectionName.alwaysHidden),
        (900, .hidden),
        (200, .visible),
        (-500, .visible),
    ])
    func descendingAxis(weight: Int, expected: MenuBarSectionName) {
        #expect(StoredWeights.observedSection(
            weight: weight, hiddenDivider: 328, alwaysHiddenDivider: 1368, visibleControl: 161
        ) == expected)
    }

    @Test("An ascending axis mirrors the rule", arguments: [
        (-2000, MenuBarSectionName.alwaysHidden),
        (-900, .hidden),
        (50, .visible),
    ])
    func ascendingAxis(weight: Int, expected: MenuBarSectionName) {
        #expect(StoredWeights.observedSection(
            weight: weight, hiddenDivider: -328, alwaysHiddenDivider: -1368, visibleControl: -161
        ) == expected)
    }

    @Test("Without Always Hidden everything past the Hidden divider is Hidden")
    func noAlwaysHidden() {
        #expect(StoredWeights.observedSection(
            weight: 5000, hiddenDivider: 328, alwaysHiddenDivider: nil, visibleControl: 161
        ) == .hidden)
    }

    /// Out of order: an Always Hidden divider between Visible and Hidden, or on the Hidden
    /// divider, and a Hidden divider on the Visible control.
    @Test("Dividers are in order only when they run Always Hidden, Hidden, Visible control on either axis", arguments: [
        (328, 1368, 161, true),
        (-328, -1368, -161, true),
        (328, nil, 161, true),
        (328, 200, 161, false),
        (328, 100, 161, false),
        (328, 328, 161, false),
        (-328, -200, -161, false),
        (161, nil, 161, false),
    ] as [(Int, Int?, Int, Bool)])
    func dividersInOrder(hidden: Int, alwaysHidden: Int?, visibleControl: Int, ordered: Bool) {
        #expect(StoredWeights.dividersAreOrdered(
            hiddenDivider: hidden, alwaysHiddenDivider: alwaysHidden, visibleControl: visibleControl
        ) == ordered)
    }
}
