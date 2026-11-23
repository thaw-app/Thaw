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
    /// Native leaves an app it switched back on for the reveal where it is; Standard moves an
    /// item across the divider whatever Native last switched off; an item in its section stays.
    @Test(
        "Only a misplaced item is moved, and under Native only one it did not switch on for the reveal",
        arguments: [
            (HidingMethod.native, true, true, false),
            (.native, false, true, true),
            (.standard, false, true, true),
            (.standard, true, true, true),
            (.standard, false, false, false),
            (.native, false, false, false),
        ]
    )
    func shouldMove(method: HidingMethod, switchedOnForReveal: Bool, isMisplaced: Bool, moves: Bool) {
        #expect(RevealRepairDecision.shouldMove(method: method, switchedOnForReveal: switchedOnForReveal, isMisplaced: isMisplaced) == moves)
    }
}
