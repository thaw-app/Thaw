//
//  LayoutResetTargetTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@Suite("Layout reset targets")
struct LayoutResetTargetTests {
    private let hiddenBounds = CGRect(x: 100, y: 0, width: 20, height: 22)
    private let alwaysHiddenBounds = CGRect(x: 40, y: 0, width: 20, height: 22)

    @Test("Visible contains items right of the hidden divider")
    func visibleTarget() {
        let target = MenuBarItemManager.LayoutResetTarget.visible

        #expect(target.contains(
            itemBounds: CGRect(x: 120, y: 0, width: 20, height: 22),
            hiddenBounds: hiddenBounds,
            alwaysHiddenBounds: alwaysHiddenBounds
        ))
        #expect(!target.contains(
            itemBounds: CGRect(x: 70, y: 0, width: 20, height: 22),
            hiddenBounds: hiddenBounds,
            alwaysHiddenBounds: alwaysHiddenBounds
        ))
    }

    @Test("Hidden contains items between the dividers")
    func hiddenTarget() {
        let target = MenuBarItemManager.LayoutResetTarget.hidden

        #expect(target.contains(
            itemBounds: CGRect(x: 70, y: 0, width: 20, height: 22),
            hiddenBounds: hiddenBounds,
            alwaysHiddenBounds: alwaysHiddenBounds
        ))
        #expect(!target.contains(
            itemBounds: CGRect(x: 10, y: 0, width: 20, height: 22),
            hiddenBounds: hiddenBounds,
            alwaysHiddenBounds: alwaysHiddenBounds
        ))
    }

    @Test("Hidden extends leftward when Always Hidden is disabled")
    func hiddenWithoutAlwaysHiddenDivider() {
        #expect(MenuBarItemManager.LayoutResetTarget.hidden.contains(
            itemBounds: CGRect(x: 10, y: 0, width: 20, height: 22),
            hiddenBounds: hiddenBounds,
            alwaysHiddenBounds: nil
        ))
    }

    @Test("Always Hidden contains items left of its divider")
    func alwaysHiddenTarget() {
        let target = MenuBarItemManager.LayoutResetTarget.alwaysHidden

        #expect(target.contains(
            itemBounds: CGRect(x: 10, y: 0, width: 20, height: 22),
            hiddenBounds: hiddenBounds,
            alwaysHiddenBounds: alwaysHiddenBounds
        ))
        #expect(!target.contains(
            itemBounds: CGRect(x: 70, y: 0, width: 20, height: 22),
            hiddenBounds: hiddenBounds,
            alwaysHiddenBounds: alwaysHiddenBounds
        ))
    }

    @Test("Always Hidden cannot contain items without its divider")
    func alwaysHiddenWithoutDivider() {
        #expect(!MenuBarItemManager.LayoutResetTarget.alwaysHidden.contains(
            itemBounds: CGRect(x: 10, y: 0, width: 20, height: 22),
            hiddenBounds: hiddenBounds,
            alwaysHiddenBounds: nil
        ))
    }

    @Test("Only Hidden reseats every candidate in the first pass")
    func firstPassPolicy() {
        #expect(MenuBarItemManager.LayoutResetTarget.hidden.movesAllCandidatesInFirstPass)
        #expect(!MenuBarItemManager.LayoutResetTarget.visible.movesAllCandidatesInFirstPass)
        #expect(!MenuBarItemManager.LayoutResetTarget.alwaysHidden.movesAllCandidatesInFirstPass)
    }

    @Test("Only Always Hidden requires its divider")
    func dividerRequirement() {
        #expect(!MenuBarItemManager.LayoutResetTarget.hidden.requiresAlwaysHiddenDivider)
        #expect(!MenuBarItemManager.LayoutResetTarget.visible.requiresAlwaysHiddenDivider)
        #expect(MenuBarItemManager.LayoutResetTarget.alwaysHidden.requiresAlwaysHiddenDivider)
    }
}
