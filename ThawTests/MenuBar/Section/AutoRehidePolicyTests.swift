//
//  AutoRehidePolicyTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Auto-rehide policy")
struct AutoRehidePolicyTests {
    @Test("Smart focus changes wait out the remaining reveal grace period")
    func smartFocusChangeWaitsOutRevealGrace() {
        let now = ContinuousClock.now
        let shownAt = now - .milliseconds(100)

        #expect(MenuBarManager.smartRehideDelay(since: shownAt, now: now) == .milliseconds(400))
    }

    @Test("Smart focus changes retain their focus-settling delay after grace")
    func smartFocusChangeRetainsSettlingDelay() {
        let now = ContinuousClock.now
        let shownAt = now - .seconds(2)

        #expect(MenuBarManager.smartRehideDelay(since: shownAt, now: now) == .milliseconds(250))
        #expect(MenuBarManager.smartRehideDelay(since: nil, now: now) == .milliseconds(250))
    }

    @Test("External app activation triggers auto-rehide")
    func externalActivationTriggersAutoRehide() {
        #expect(
            MenuBarManager.shouldHandleAutoRehideActivation(
                activatedProcessIdentifier: 42,
                currentProcessIdentifier: 7
            )
        )
    }

    @Test("Thaw's own activation does not rehide its reveal")
    func ownActivationDoesNotRehideReveal() {
        #expect(
            !MenuBarManager.shouldHandleAutoRehideActivation(
                activatedProcessIdentifier: 7,
                currentProcessIdentifier: 7
            )
        )
    }
}
