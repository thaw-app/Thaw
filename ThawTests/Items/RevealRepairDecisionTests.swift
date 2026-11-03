//
//  RevealRepairDecisionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("A reveal's repair leaves the apps Native hiding switched back on where macOS put them")
struct RevealRepairDecisionTests {
    @Test("Native: an app switched back on for the reveal is not moved")
    func nativeSwitchedOnIsNotMoved() {
        #expect(!RevealRepairDecision.shouldMove(method: .native, switchedOnForReveal: true, isMisplaced: true))
    }

    @Test("Native: an app Native hiding did not switch off is moved when it is across the divider")
    func nativeUnmanagedMisplacedIsMoved() {
        #expect(RevealRepairDecision.shouldMove(method: .native, switchedOnForReveal: false, isMisplaced: true))
    }

    @Test("Standard: an item across the divider is moved, whatever Native hiding last switched off")
    func standardMisplacedIsMoved() {
        #expect(RevealRepairDecision.shouldMove(method: .standard, switchedOnForReveal: false, isMisplaced: true))
        #expect(RevealRepairDecision.shouldMove(method: .standard, switchedOnForReveal: true, isMisplaced: true))
    }

    @Test("An item already in its section is not moved, under either method")
    func placedItemIsNotMoved() {
        #expect(!RevealRepairDecision.shouldMove(method: .standard, switchedOnForReveal: false, isMisplaced: false))
        #expect(!RevealRepairDecision.shouldMove(method: .native, switchedOnForReveal: false, isMisplaced: false))
    }
}
