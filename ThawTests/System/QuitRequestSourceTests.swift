//
//  QuitRequestSourceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreServices
import Foundation
import Testing
@testable import Thaw

/// 2026-10-22: Thaw quit at the same moment as another app while Steam ran,
/// and the log couldn't say who asked.
@Suite("The log names who asked Thaw to quit")
struct QuitRequestSourceTests {
    @Test func aQuitWithoutAnAppleEventCameFromThaw() {
        #expect(QuitRequestSource.describe(senderPID: nil, senderName: nil, reason: nil, ownPID: 42) == "from Thaw itself")
    }

    @Test func aQuitFromAnotherAppNamesIt() {
        #expect(QuitRequestSource.describe(senderPID: 812, senderName: "Steam", reason: nil, ownPID: 42) == "by Steam (pid 812)")
    }

    @Test func anUnnamedSenderKeepsItsPID() {
        #expect(QuitRequestSource.describe(senderPID: 812, senderName: nil, reason: nil, ownPID: 42) == "by pid 812")
    }

    @Test func aQuitSentByThawItselfSaysSo() {
        #expect(QuitRequestSource.describe(senderPID: 42, senderName: "Thaw", reason: nil, ownPID: 42) == "from Thaw itself")
    }

    @Test func aLogoutGivesItsReason() {
        let reason = OSType(kAELogOut)
        #expect(
            QuitRequestSource.describe(senderPID: 98, senderName: "loginwindow", reason: reason, ownPID: 42)
                == "by loginwindow (pid 98), reason logo"
        )
    }

    @Test func fourCharCodesReadAsTheirLetters() {
        #expect(QuitRequestSource.string(fromFourCharCode: 0x7175_6974) == "quit")
    }

    /// Outside a quit event, as in a test, the request reads as Thaw's own.
    @MainActor
    @Test func theCurrentRequestOutsideAnEventIsThaws() {
        #expect(QuitRequestSource.current() == "from Thaw itself")
    }
}
