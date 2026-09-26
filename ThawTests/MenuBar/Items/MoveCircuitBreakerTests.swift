//
//  MoveCircuitBreakerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// When the breaker trips, how long it stays open, and how it clears.
///
/// Every move on macOS 26 is a synthetic drag, so the key tests assert a large
/// one-pass apply never trips it; only one item dragged repeatedly, or a run of
/// failed moves, does.
@MainActor
@Suite("Move circuit breaker")
struct MoveCircuitBreakerTests {
    private final class ManualClock {
        var now = ContinuousClock.now
        func advance(by duration: Duration) {
            now = now.advanced(by: duration)
        }
    }

    private let clock = ManualClock()

    private func makeBreaker() -> MoveCircuitBreaker {
        MoveCircuitBreaker { [clock] in clock.now }
    }

    @Test("Many different items moved once each do not trip it")
    func distinctItemsDoNotTrip() {
        let breaker = makeBreaker()
        for index in 0 ..< 50 {
            breaker.note(.move(identifier: "com.example.item\(index)"))
        }
        #expect(!breaker.isOpen)
    }

    @Test("One item moved past the limit trips it")
    func sameItemRepeatsTrip() {
        let breaker = makeBreaker()
        for _ in 0 ..< MoveCircuitBreaker.sameItemMoveLimit {
            #expect(!breaker.note(.move(identifier: "com.example.dancer")))
        }
        #expect(breaker.note(.move(identifier: "com.example.dancer")))
        #expect(breaker.isOpen)
    }

    @Test("Repeats that fall out of the window do not add up")
    func repeatsOutsideWindowDoNotTrip() {
        let breaker = makeBreaker()
        for _ in 0 ..< MoveCircuitBreaker.sameItemMoveLimit * 3 {
            breaker.note(.move(identifier: "com.example.slow"))
            clock.advance(by: MoveCircuitBreaker.window / MoveCircuitBreaker.sameItemMoveLimit + .seconds(1))
        }
        #expect(!breaker.isOpen)
    }

    @Test("Failed moves past the limit trip it")
    func failuresTrip() {
        let breaker = makeBreaker()
        for _ in 0 ..< MoveCircuitBreaker.failureLimit {
            #expect(!breaker.note(.failedMove))
        }
        #expect(breaker.note(.failedMove))
    }

    @Test("It closes after the cooldown")
    func closesAfterCooldown() {
        let breaker = makeBreaker()
        tripOnFailures(breaker)
        clock.advance(by: MoveCircuitBreaker.initialCooldown - .seconds(1))
        #expect(breaker.isOpen)
        clock.advance(by: .seconds(2))
        #expect(!breaker.isOpen)
    }

    @Test("A quick second trip stays open twice as long")
    func backoffDoubles() {
        let breaker = makeBreaker()
        tripOnFailures(breaker)
        clock.advance(by: MoveCircuitBreaker.initialCooldown + .seconds(1))
        tripOnFailures(breaker)
        clock.advance(by: MoveCircuitBreaker.initialCooldown + .seconds(1))
        #expect(breaker.isOpen)
        clock.advance(by: MoveCircuitBreaker.initialCooldown)
        #expect(!breaker.isOpen)
    }

    @Test("A trip after a quiet period starts the backoff over")
    func backoffResets() {
        let breaker = makeBreaker()
        tripOnFailures(breaker)
        clock.advance(by: MoveCircuitBreaker.backoffResetInterval + .seconds(1))
        tripOnFailures(breaker)
        clock.advance(by: MoveCircuitBreaker.initialCooldown + .seconds(1))
        #expect(!breaker.isOpen)
    }

    @Test("A user's move clears it and forgets the counted moves")
    func userOverrideClears() {
        let breaker = makeBreaker()
        tripOnFailures(breaker)
        breaker.noteUserOverride()
        #expect(!breaker.isOpen)
        #expect(!breaker.note(.failedMove))
    }

    private func tripOnFailures(_ breaker: MoveCircuitBreaker) {
        for _ in 0 ... MoveCircuitBreaker.failureLimit {
            breaker.note(.failedMove)
        }
        #expect(breaker.isOpen)
    }
}
