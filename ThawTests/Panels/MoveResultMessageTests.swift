//
//  MoveResultMessageTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Move result message")
struct MoveResultMessageTests {
    @Test("A move that landed says where the item went")
    func landed() {
        let message = MoveResultMessage.make(itemName: "Slack", sectionTitle: "Hidden", committed: true, landed: true)
        #expect(message == MoveResultMessage(symbol: "checkmark", text: "Moved Slack to Hidden"))
    }

    @Test("A move that didn't hold says so")
    func didNotStay() {
        let message = MoveResultMessage.make(itemName: "Slack", sectionTitle: "Hidden", committed: true, landed: false)
        #expect(message.text == "Slack didn’t stay in Hidden")
        #expect(message.symbol == "exclamationmark.triangle")
    }

    @Test("A move that was never made says it couldn't move", arguments: [true, false])
    func notCommitted(landed: Bool) {
        let message = MoveResultMessage.make(itemName: "Slack", sectionTitle: "Hidden", committed: false, landed: landed)
        #expect(message.text == "Couldn’t move Slack")
    }
}
