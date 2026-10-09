//
//  BoundaryRepairBreakerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("The boundary repair gives up on an item after repeated failures, and tries again later")
struct BoundaryRepairBreakerTests {
    private let start = Date(timeIntervalSince1970: 1000)

    @Test("Failures count up, and the one that reaches the limit suppresses the item")
    func failuresReachTheLimit() {
        var breaker = BoundaryRepairBreaker<String>()

        let first = breaker.record(repaired: false, for: "a", tripLimit: 3, now: start)
        let second = breaker.record(repaired: false, for: "a", tripLimit: 3, now: start)
        #expect(first == .init(suppressed: false, trips: 1))
        #expect(second == .init(suppressed: false, trips: 2))
        #expect(breaker.trips(for: "a") == 2)
        #expect(!breaker.isSuppressed("a"))

        let third = breaker.record(repaired: false, for: "a", tripLimit: 3, now: start)
        #expect(third == .init(suppressed: true, trips: 3))
        #expect(breaker.isSuppressed("a"))
        #expect(breaker.trips(for: "a") == 0)
        #expect(breaker.suppressedCount == 1)
    }

    @Test("A repair that worked clears the count")
    func successClearsTheCount() {
        var breaker = BoundaryRepairBreaker<String>()
        breaker.record(repaired: false, for: "a", tripLimit: 3, now: start)

        let outcome = breaker.record(repaired: true, for: "a", tripLimit: 3, now: start)

        #expect(outcome == .init(suppressed: false, trips: 0))
        #expect(breaker.trips(for: "a") == 0)
    }

    @Test("A suppression holds until its cooldown has passed")
    func suppressionHoldsForTheCooldown() {
        var breaker = BoundaryRepairBreaker<String>()
        breaker.suppress("a", at: start)

        #expect(breaker.suppressionHolds(for: "a", now: start + 59, cooldown: 60))
        #expect(!breaker.suppressionHolds(for: "a", now: start + 60, cooldown: 60))
        #expect(!breaker.suppressionHolds(for: "never suppressed", now: start, cooldown: 60))
    }

    @Test("Re-arming the expired ones leaves the recent ones suppressed, and forgets the count")
    func rearmExpired() {
        var breaker = BoundaryRepairBreaker<String>()
        breaker.suppress("old", at: start)
        breaker.suppress("recent", at: start + 50)
        breaker.addTrip(for: "old")

        let rearmed = breaker.rearmExpired(now: start + 60, cooldown: 60)

        #expect(rearmed == 1)
        #expect(!breaker.isSuppressed("old"))
        #expect(breaker.trips(for: "old") == 0)
        #expect(breaker.isSuppressed("recent"))
    }

    @Test("Re-arming one item clears its suppression and its count, and leaves the others")
    func rearmOne() {
        var breaker = BoundaryRepairBreaker<String>()
        breaker.suppress("a", at: start)
        breaker.suppress("b", at: start)
        breaker.addTrip(for: "a")

        breaker.rearm("a")

        #expect(!breaker.isSuppressed("a"))
        #expect(breaker.trips(for: "a") == 0)
        #expect(breaker.isSuppressed("b"))
    }

    @Test("Re-arming everything empties it")
    func rearmAll() {
        var breaker = BoundaryRepairBreaker<String>()
        breaker.suppress("a", at: start)
        breaker.addTrip(for: "b")

        breaker.rearmAll()

        #expect(breaker.suppressedCount == 0)
        #expect(breaker.trips(for: "b") == 0)
    }

    @Test("Items that have left the bar are forgotten")
    func pruneToLiveItems() {
        var breaker = BoundaryRepairBreaker<String>()
        breaker.suppress("gone", at: start)
        breaker.suppress("here", at: start)
        breaker.addTrip(for: "gone")
        breaker.addTrip(for: "here")

        breaker.prune(keeping: ["here"])

        #expect(!breaker.isSuppressed("gone"))
        #expect(breaker.trips(for: "gone") == 0)
        #expect(breaker.isSuppressed("here"))
        #expect(breaker.trips(for: "here") == 1)
    }

    @Test("Suppressing by hand leaves the count alone")
    func suppressKeepsTheCount() {
        var breaker = BoundaryRepairBreaker<String>()
        breaker.addTrip(for: "a")
        breaker.addTrip(for: "a")
        breaker.suppress("a", at: start)
        #expect(breaker.trips(for: "a") == 2)
    }
}
