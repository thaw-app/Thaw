//
//  SpacingApplyChoiceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Spacing apply choice")
struct SpacingApplyChoiceTests {
    @Test("The stored settings read back as one choice")
    func reads() {
        #expect(SpacingApplyChoice(mode: .relaunchApps, confirms: true) == .askFirst)
        #expect(SpacingApplyChoice(mode: .relaunchApps, confirms: false) == .relaunchNow)
        #expect(SpacingApplyChoice(mode: .writeOnly, confirms: true) == .waitForRestart)
        #expect(SpacingApplyChoice(mode: .writeOnly, confirms: false) == .waitForRestart)
    }

    @Test("Each choice writes back the settings it was read from", arguments: SpacingApplyChoice.allCases)
    func roundTrip(choice: SpacingApplyChoice) {
        let confirms = choice.confirms ?? true
        #expect(SpacingApplyChoice(mode: choice.mode, confirms: confirms) == choice)
    }

    @Test("Waiting for a restart leaves the confirmation switch alone")
    func waitingKeepsSwitch() {
        #expect(SpacingApplyChoice.waitForRestart.confirms == nil)
        #expect(SpacingApplyChoice.waitForRestart.mode == .writeOnly)
    }
}
