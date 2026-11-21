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
@Suite("Showing an item when its icon changes", .serialized, .scratchDefaults)
struct AlertRevealTests {
    private let identifier = "com.example.mail:Item"

    @Test("Chosen items are watched only while Triggers is on")
    func watchedFollowsTriggers() {
        let saved: Set = [identifier]
        #expect(MenuBarItemAlertReveals.watched(saved: saved, triggersOn: true) == saved)
        #expect(MenuBarItemAlertReveals.watched(saved: saved, triggersOn: false).isEmpty)
    }

    @Test("A saved choice with Triggers off asks for no capture off screen")
    func noBackgroundDemandWithTriggersOff() {
        MenuBarItemAlertReveals.setEnabled(true, for: identifier)
        defer { MenuBarItemAlertReveals.setEnabled(false, for: identifier) }
        let imageCache = MenuBarItemImageCache()
        #expect(imageCache.hasBackgroundCaptureDemand(triggersOn: true))
        #expect(!imageCache.hasBackgroundCaptureDemand(triggersOn: false))
        #expect(!imageCache.hasBackgroundCaptureDemand(), "Without an app state the module counts as off")
    }

    @Test("A saved choice with Triggers off keeps no item in a pass that uses app icons")
    func captureDemandFollowsTriggers() {
        MenuBarItemAlertReveals.setEnabled(true, for: identifier)
        defer { MenuBarItemAlertReveals.setEnabled(false, for: identifier) }
        let imageCache = MenuBarItemImageCache()
        #expect(imageCache.captureDemand(triggersOn: true).alertRevealIdentifiers == [identifier])
        #expect(imageCache.captureDemand(triggersOn: false).alertRevealIdentifiers.isEmpty)
        #expect(imageCache.captureDemand().alertRevealIdentifiers.isEmpty)
    }
}
