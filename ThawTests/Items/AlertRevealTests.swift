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
}
