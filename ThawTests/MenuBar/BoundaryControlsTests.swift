//
//  BoundaryControlsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// Which dividers a reveal's boundary check judges items against.
@MainActor
@Suite("Dividers for the boundary check")
struct BoundaryControlsTests {
    private static func control(_ tag: MenuBarItemTag, x: CGFloat, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem(
            tag: tag, windowID: windowID, ownerPID: 1, sourcePID: 1,
            bounds: CGRect(x: x, y: 3, width: 2, height: 24), title: "control", isOnScreen: true
        )
    }

    // The bar from the log: the collapsed Always Hidden divider sat beside the Hidden divider.
    private let pair = ControlItemPair(
        hidden: control(.hiddenControlItem, x: 1685.5, windowID: 1),
        alwaysHidden: control(.alwaysHiddenControlItem, x: 1684.5, windowID: 2)
    )

    @Test("Showing Hidden ignores the collapsed Always Hidden divider")
    func hiddenRevealDropsAlwaysHidden() {
        let controls = ControlOrderRules.boundaryControls(pair, revealedSection: .hidden)
        #expect(controls.hidden.windowID == 1)
        #expect(controls.alwaysHidden == nil)
    }

    @Test("Showing Always Hidden keeps both dividers")
    func alwaysHiddenRevealKeepsBoth() {
        let controls = ControlOrderRules.boundaryControls(pair, revealedSection: .alwaysHidden)
        #expect(controls.hidden.windowID == 1)
        #expect(controls.alwaysHidden?.windowID == 2)
    }

    @Test("A Visible pass ignores the Always Hidden divider")
    func visiblePassDropsAlwaysHidden() {
        #expect(ControlOrderRules.boundaryControls(pair, revealedSection: .visible).alwaysHidden == nil)
    }

    @Test("Without Always Hidden nothing changes")
    func noAlwaysHidden() {
        let single = ControlItemPair(hidden: pair.hidden, alwaysHidden: nil)
        #expect(ControlOrderRules.boundaryControls(single, revealedSection: .alwaysHidden).alwaysHidden == nil)
        #expect(ControlOrderRules.boundaryControls(single, revealedSection: .hidden).hidden.windowID == 1)
    }
}
