//
//  ManualMembershipTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

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
        #expect(MenuBarItemManager.observedSection(
            weight: weight, hiddenDivider: 328, alwaysHiddenDivider: 1368, visibleControl: 161
        ) == expected)
    }

    @Test("An ascending axis mirrors the rule")
    func ascendingAxis() {
        #expect(MenuBarItemManager.observedSection(
            weight: -2000, hiddenDivider: -328, alwaysHiddenDivider: -1368, visibleControl: -161
        ) == .alwaysHidden)
        #expect(MenuBarItemManager.observedSection(
            weight: -900, hiddenDivider: -328, alwaysHiddenDivider: -1368, visibleControl: -161
        ) == .hidden)
        #expect(MenuBarItemManager.observedSection(
            weight: 50, hiddenDivider: -328, alwaysHiddenDivider: -1368, visibleControl: -161
        ) == .visible)
    }

    @Test("Without Always Hidden everything past the Hidden divider is Hidden")
    func noAlwaysHidden() {
        #expect(MenuBarItemManager.observedSection(
            weight: 5000, hiddenDivider: 328, alwaysHiddenDivider: nil, visibleControl: 161
        ) == .hidden)
    }
}
