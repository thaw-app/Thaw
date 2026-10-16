//
//  MenuBarOverlayPanelSpaceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers `MenuBarOverlayPanel.isStranded(panelSpaces:currentSpace:globalActiveSpace:ownsActiveMenuBar:)`,
/// the pure decision behind the space migration in `show()` (#794). The rest
/// talks to the window server.
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
        // A known per-display space decides alone, even when the global
        // active space points elsewhere.
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
        // On macOS 26 the per-display query can stop answering. The display
        // owning the active menu bar can use the global active space instead.
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
        // The global active space says nothing about sibling displays, and a
        // wrong order-out flickers the bar on every housekeeping pass.
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
        // Switching display B's space must not order out display A's panel.
        let stranded = MenuBarOverlayPanel.isStranded(
            panelSpaces: [30],
            currentSpace: 30,
            globalActiveSpace: 30,
            ownsActiveMenuBar: false
        )
        #expect(!stranded)
    }
}
