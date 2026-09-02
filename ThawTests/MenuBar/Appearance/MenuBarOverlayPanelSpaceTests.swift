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

/// Covers `MenuBarOverlayPanel.isStranded(panelSpaces:currentSpace:globalActiveSpace:ownsActiveMenuBar:)`,
/// the pure decision behind the space migration in `show()` (#794). The rest
/// of the migration talks to the window server (per-display current space,
/// the panel's own space list) and isn't practically unit-testable; this is
/// the one piece of its logic that is.
@Suite("Menu bar overlay panel spaces")
struct MenuBarOverlayPanelSpaceTests {
    @Test("A panel on the owning display's current space is not stranded")
    func onCurrentSpaceIsNotStranded() {
        let stranded = MenuBarOverlayPanel.isStranded(
            panelSpaces: [10],
            currentSpace: 10,
            globalActiveSpace: 10,
            ownsActiveMenuBar: false
        )
        #expect(!stranded)
    }

    @Test("A panel left behind by a space switch is stranded")
    func leftBehindBySwitchIsStranded() {
        // Panel sits on space 10 while its display moved on to space 11.
        let stranded = MenuBarOverlayPanel.isStranded(
            panelSpaces: [10],
            currentSpace: 11,
            globalActiveSpace: 11,
            ownsActiveMenuBar: false
        )
        #expect(stranded)
    }

    @Test("A panel that was never ordered is stranded")
    func neverOrderedIsStranded() {
        // No spaces at all until the first order-front places it.
        let stranded = MenuBarOverlayPanel.isStranded(
            panelSpaces: [],
            currentSpace: 10,
            globalActiveSpace: 10,
            ownsActiveMenuBar: false
        )
        #expect(stranded)
    }

    @Test("A known current space beats the fallback")
    func knownCurrentSpaceBeatsFallback() {
        // The display's own space is authoritative: even with the panel
        // owning the active menu bar and the global active space pointing
        // elsewhere, a known per-display space decides the verdict alone.
        let stranded = MenuBarOverlayPanel.isStranded(
            panelSpaces: [10],
            currentSpace: 10,
            globalActiveSpace: 11,
            ownsActiveMenuBar: true
        )
        #expect(!stranded)
    }

    @Test("An unknown current space falls back to the global active space on the active display")
    func unknownCurrentSpaceFallsBackOnActiveDisplay() {
        // #794: on macOS 26 setups where the per-display query stops
        // answering, the display that owns the active menu bar can still
        // judge the panel against the global active space — the two
        // coincide there by definition. A panel the switch left behind is
        // stranded; one that followed is not.
        let stranded = MenuBarOverlayPanel.isStranded(
            panelSpaces: [10],
            currentSpace: nil,
            globalActiveSpace: 11,
            ownsActiveMenuBar: true
        )
        #expect(stranded)

        let followed = MenuBarOverlayPanel.isStranded(
            panelSpaces: [11],
            currentSpace: nil,
            globalActiveSpace: 11,
            ownsActiveMenuBar: true
        )
        #expect(!followed)
    }

    @Test("An unknown current space does not strand a panel on a sibling display")
    func unknownCurrentSpaceIsNotStrandedOnSiblingDisplay() {
        // The fallback must not reach sibling displays: the global active
        // space says nothing about their current space, and a wrong
        // order-out would flicker the bar on every housekeeping pass.
        let stranded = MenuBarOverlayPanel.isStranded(
            panelSpaces: [10],
            currentSpace: nil,
            globalActiveSpace: 11,
            ownsActiveMenuBar: false
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
            currentSpace: 30,
            globalActiveSpace: 30,
            ownsActiveMenuBar: false
        )
        #expect(!stranded)
    }
}
