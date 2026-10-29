//
//  MoveCircuitBreakerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("The move circuit breaker pauses runaway reordering")
struct MoveCircuitBreakerTests {
    @Test("A fresh breaker is closed")
    func startsClosed() {
        let breaker = MoveCircuitBreaker()
        #expect(!breaker.isOpen)
        #expect(breaker.stateDescription.contains("trips=0"))
        #expect(breaker.stateDescription.contains("open=false"))
    }

    @Test("Synthetic drags up to the limit pass and one more trips the breaker")
    func dragLimitTrips() {
        let breaker = MoveCircuitBreaker()
        for _ in 0 ..< MoveCircuitBreaker.dragLimit {
            #expect(!breaker.note(.syntheticDrag))
        }
        #expect(!breaker.isOpen)

        #expect(breaker.note(.syntheticDrag))
        #expect(breaker.isOpen)
        #expect(breaker.stateDescription.contains("trips=1"))
        #expect(breaker.stateDescription.contains("open=true"))
    }

    @Test("Store writes trip only past their own, larger limit")
    func storeWriteLimitTrips() {
        let breaker = MoveCircuitBreaker()
        for _ in 0 ..< MoveCircuitBreaker.storeWriteLimit {
            breaker.note(.storeWrite)
        }
        #expect(!breaker.isOpen)
        #expect(breaker.note(.storeWrite))
        #expect(breaker.isOpen)
    }

    @Test("Failed verifications trip past their limit")
    func failureLimitTrips() {
        let breaker = MoveCircuitBreaker()
        for _ in 0 ..< MoveCircuitBreaker.failureLimit {
            breaker.note(.failedVerification)
        }
        #expect(!breaker.isOpen)
        #expect(breaker.note(.failedVerification))
    }

    @Test("Mixed signals are counted per kind, not together")
    func signalsCountSeparately() {
        let breaker = MoveCircuitBreaker()
        for _ in 0 ..< MoveCircuitBreaker.dragLimit {
            breaker.note(.syntheticDrag)
            breaker.note(.failedVerification)
            breaker.note(.storeWrite)
        }
        #expect(!breaker.isOpen)
    }

    @Test("Any signal reports open while the breaker is open")
    func openBreakerAnswersOpen() {
        let breaker = MoveCircuitBreaker()
        for _ in 0 ... MoveCircuitBreaker.dragLimit {
            breaker.note(.syntheticDrag)
        }
        #expect(breaker.note(.storeWrite))
        #expect(breaker.stateDescription.contains("trips=1"))
    }

    @Test("A user move clears the breaker but keeps the escalated cooldown")
    func userOverrideClearsButKeepsBackoff() {
        let breaker = MoveCircuitBreaker()
        for _ in 0 ... MoveCircuitBreaker.dragLimit {
            breaker.note(.syntheticDrag)
        }
        #expect(breaker.isOpen)
        #expect(breaker.stateDescription.contains("cooldown=120"))

        breaker.noteUserOverride()

        #expect(!breaker.isOpen)
        #expect(breaker.stateDescription.contains("window=0"))
        #expect(breaker.stateDescription.contains("cooldown=120"))

        // A second storm right away backs off longer than the first.
        for _ in 0 ... MoveCircuitBreaker.dragLimit {
            breaker.note(.syntheticDrag)
        }
        #expect(breaker.isOpen)
        #expect(breaker.stateDescription.contains("trips=2"))
        #expect(breaker.stateDescription.contains("cooldown=240"))
    }
}
