//
//  MenuBarOverlayPanelSpaceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers `MenuBarOverlayPanel.isStranded(panelSpaces:currentSpace:)`, the
/// pure decision behind the space migration in `show()` (#794). The rest of
/// the migration talks to the window server (per-display current space and
/// the panel's own space list) and isn't practically unit-testable; this is
/// the one piece of its logic that is.
@Suite("Menu bar overlay panel spaces")
struct MenuBarOverlayPanelSpaceTests {
    @Test("A panel on the owning display's current space is not stranded")
    func onCurrentSpaceIsNotStranded() {
        let stranded = MenuBarOverlayPanel.isStranded(
            panelSpaces: [10],
            currentSpace: 10
        )
        #expect(!stranded)
    }

    @Test("A panel left behind by a space switch is stranded")
    func leftBehindBySwitchIsStranded() {
        // Panel sits on space 10 while its display moved on to space 11.
        let stranded = MenuBarOverlayPanel.isStranded(
            panelSpaces: [10],
            currentSpace: 11
        )
        #expect(stranded)
    }

    @Test("A panel that was never ordered is stranded")
    func neverOrderedIsStranded() {
        // No spaces at all until the first order-front places it.
        let stranded = MenuBarOverlayPanel.isStranded(
            panelSpaces: [],
            currentSpace: 10
        )
        #expect(stranded)
    }

    @Test("An unknown owning display's current space does not strand the panel")
    func unknownCurrentSpaceIsNotStranded() {
        // Without per-display space info, `show()` keeps the panel where it
        // is rather than ordering it out on a guess.
        let stranded = MenuBarOverlayPanel.isStranded(
            panelSpaces: [10],
            currentSpace: nil
        )
        #expect(!stranded)
    }

    @Test("A sibling display's space change does not strand the panel")
    func siblingDisplaySwitchDoesNotStrand() {
        // With distinct spaces per display, switching display B's space must
        // not order out display A's panel: A's panel still sits on A's
        // current space.
        let stranded = MenuBarOverlayPanel.isStranded(
            panelSpaces: [30],
            currentSpace: 30
        )
        #expect(!stranded)
    }
}
