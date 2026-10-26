//
//  AlertRevealPolicyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("An icon change reveals its item at most once per cooldown")
struct AlertRevealPolicyTests {
    private let start = ContinuousClock.now

    @Test("A second change inside the cooldown does not reveal again")
    func holdsInsideCooldown() {
        var policy = AlertRevealPolicy()
        let first = policy.shouldReveal("a", now: start)
        let early = policy.shouldReveal("a", now: start + policy.cooldown - .milliseconds(1))
        #expect(first)
        #expect(!early)
        #expect(policy.lastReveals["a"] == start)
    }

    @Test("A change once the cooldown has passed reveals again")
    func revealsAfterCooldown() {
        var policy = AlertRevealPolicy()
        let first = policy.shouldReveal("a", now: start)
        let later = policy.shouldReveal("a", now: start + policy.cooldown)
        #expect(first)
        #expect(later)
        #expect(policy.lastReveals["a"] == start + policy.cooldown)
    }

    @Test("Each item has its own cooldown")
    func cooldownIsPerItem() {
        var policy = AlertRevealPolicy()
        let first = policy.shouldReveal("a", now: start)
        let other = policy.shouldReveal("b", now: start)
        #expect(first)
        #expect(other)
    }
}
