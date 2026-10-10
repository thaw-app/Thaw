//
//  ControlTrioOrderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// Tests for the cheap "are the controls still Always-Hidden | Hidden |
/// Visible?" question the reveal path asks before it re-lays the structural
/// permutation.
struct ControlTrioOrderTests {
    @Test("the canonical Always-Hidden | Hidden | Visible order is recognised")
    func canonicalOrder() {
        #expect(MenuBarItemManager.controlTrioInCanonicalOrder(
            alwaysHidden: control(midX: 10),
            hidden: control(midX: 20),
            visible: control(midX: 30)
        ))
    }

    @Test("a reversed trio is not in order")
    func reversedOrder() {
        #expect(!MenuBarItemManager.controlTrioInCanonicalOrder(
            alwaysHidden: control(midX: 30),
            hidden: control(midX: 20),
            visible: control(midX: 10)
        ))
    }

    @Test("a single inversion anywhere in the trio is rejected")
    func partialInversion() {
        #expect(!MenuBarItemManager.controlTrioInCanonicalOrder(
            alwaysHidden: control(midX: 10),
            hidden: control(midX: 30),
            visible: control(midX: 20)
        ))
        #expect(!MenuBarItemManager.controlTrioInCanonicalOrder(
            alwaysHidden: control(midX: 20),
            hidden: control(midX: 10),
            visible: control(midX: 30)
        ))
    }

    @Test("without an Always-Hidden divider only Hidden before Visible is required")
    func alwaysHiddenDisabled() {
        #expect(MenuBarItemManager.controlTrioInCanonicalOrder(
            alwaysHidden: nil,
            hidden: control(midX: 20),
            visible: control(midX: 30)
        ))
        #expect(!MenuBarItemManager.controlTrioInCanonicalOrder(
            alwaysHidden: nil,
            hidden: control(midX: 30),
            visible: control(midX: 20)
        ))
    }

    @Test("a one-pixel tie a reflow leaves behind still reads as in order")
    func tieReadsAsInOrder() {
        #expect(MenuBarItemManager.controlTrioInCanonicalOrder(
            alwaysHidden: control(midX: 20),
            hidden: control(midX: 20),
            visible: control(midX: 20)
        ))
    }

    private func control(midX: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: .hiddenControlItem,
            windowID: 1,
            ownerPID: 1,
            sourcePID: 1,
            bounds: CGRect(x: midX, y: 0, width: 0, height: 0),
            title: "control",
            isOnScreen: false
        )
    }
}
