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

    @Test("The restarting choices warn that unsaved work may be lost", arguments: [SpacingApplyChoice.askFirst, .relaunchNow])
    func restartingNoticeWarns(choice: SpacingApplyChoice) {
        let message = String(localized: choice.relaunchNotice.message)
        #expect(message.contains("every app with a menu bar item"))
        #expect(message.contains("unsaved work"))
        #expect(message.contains("Connecting or disconnecting a display only saves"))
    }

    @Test("Restarting right away says it doesn't ask and can happen again with each profile")
    func relaunchNowNoticeSaysItRepeats() {
        let message = String(localized: SpacingApplyChoice.relaunchNow.relaunchNotice.message)
        #expect(message.contains("doesn’t ask first"))
        #expect(message.contains("each time a profile with different spacing is applied"))
    }

    @Test("Waiting promises no restart")
    func waitingNoticeRestartsNothing() {
        let notice = SpacingApplyChoice.waitForRestart.relaunchNotice
        #expect(String(localized: notice.message).contains("without restarting any app"))
        #expect(!String(localized: notice.message).contains("unsaved"))
    }
}
