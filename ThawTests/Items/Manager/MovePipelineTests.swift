//
//  MovePipelineTests.swift
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
        for _ in 0 ..< MoveCircuitBreaker.failureLimit {
            breaker.note(.failedVerification)
            breaker.note(.storeWrite)
        }
        #expect(!breaker.isOpen)
    }

    @Test("Any signal reports open while the breaker is open")
    func openBreakerAnswersOpen() {
        let breaker = MoveCircuitBreaker()
        for _ in 0 ... MoveCircuitBreaker.failureLimit {
            breaker.note(.failedVerification)
        }
        #expect(breaker.note(.storeWrite))
        #expect(breaker.stateDescription.contains("trips=1"))
    }

    @Test("A user move clears the breaker but keeps the escalated cooldown")
    func userOverrideClearsButKeepsBackoff() {
        let breaker = MoveCircuitBreaker()
        for _ in 0 ... MoveCircuitBreaker.failureLimit {
            breaker.note(.failedVerification)
        }
        #expect(breaker.isOpen)
        #expect(breaker.stateDescription.contains("cooldown=120"))

        breaker.noteUserOverride()

        #expect(!breaker.isOpen)
        #expect(breaker.stateDescription.contains("window=0"))
        #expect(breaker.stateDescription.contains("cooldown=120"))

        // A second storm right away backs off longer than the first.
        for _ in 0 ... MoveCircuitBreaker.failureLimit {
            breaker.note(.failedVerification)
        }
        #expect(breaker.isOpen)
        #expect(breaker.stateDescription.contains("trips=2"))
        #expect(breaker.stateDescription.contains("cooldown=240"))
    }
}

@MainActor
@Suite("The move pipeline monitor records what each reorder did")
struct MovePipelineMonitorTests {
    @Test("A store move counts and records a preferred-position entry")
    func storeMoveRecord() throws {
        let monitor = MovePipelineMonitor()

        monitor.recordStoreMove(item: "Clock", destination: "Hidden", satisfied: true)

        #expect(monitor.storeMoveCount == 1)
        let record = try #require(monitor.records.first)
        #expect(record.itemDescription == "Clock")
        #expect(record.destinationDescription == "Hidden")
        #expect(record.succeeded)
    }

    @Test("Records are newest first and capped at 25")
    func recordsAreCapped() {
        let monitor = MovePipelineMonitor()
        for index in 0 ..< 30 {
            monitor.recordStoreMove(item: "Item \(index)", destination: "Hidden", satisfied: index.isMultiple(of: 2))
        }
        #expect(monitor.records.count == 25)
        #expect(monitor.records.first?.itemDescription == "Item 29")
        #expect(monitor.records.last?.itemDescription == "Item 5")
        #expect(monitor.storeMoveCount == 30)
    }

    @Test("An unreachable position table is remembered")
    func storeUnavailable() {
        let monitor = MovePipelineMonitor()
        #expect(!monitor.sawStoreUnavailable)
        monitor.recordStoreUnavailable()
        #expect(monitor.sawStoreUnavailable)
    }
}
