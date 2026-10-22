//
//  AlertRevealTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Showing an item when its icon changes")
struct AlertRevealTests {
    @Test("Chosen items are watched only while Triggers is on")
    func watchedFollowsTriggers() {
        let saved: Set = ["com.example.mail:Item"]
        #expect(MenuBarItemAlertReveals.watched(saved: saved, triggersOn: true) == saved)
        #expect(MenuBarItemAlertReveals.watched(saved: saved, triggersOn: false).isEmpty)
    }

    @Test("An item shows again only after the cooldown")
    func cooldown() {
        var policy = AlertRevealPolicy(cooldown: 45)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let first = policy.shouldReveal("mail", now: start)
        let tooSoon = policy.shouldReveal("mail", now: start.addingTimeInterval(44))
        let otherItem = policy.shouldReveal("chat", now: start.addingTimeInterval(44))
        let afterCooldown = policy.shouldReveal("mail", now: start.addingTimeInterval(45))
        #expect(first)
        #expect(!tooSoon)
        #expect(otherItem, "Each item has its own cooldown")
        #expect(afterCooldown)
    }
}
