//
//  BulkMoveCoordinationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Bulk move coordination")
struct BulkMoveCoordinationTests {
    typealias Outcome = MenuBarItemManager.CacheDrivenMoveOutcome
    typealias State = MenuBarItemManager.BatchMovePreflightState

    private let initialTimestamp = ContinuousClock.now

    @Test("Only failed cache-driven moves suppress recovery side effects", arguments: [
        (Outcome.noAttempt, false, false, false),
        (Outcome.completed, true, false, false),
        (Outcome.failedAttempt, true, true, true),
    ])
    @MainActor
    func cacheDrivenMoveRecoveryPolicy(
        outcome: Outcome,
        needsRecache: Bool,
        suppressesMoves: Bool,
        suppressesPersistence: Bool
    ) {
        #expect(outcome.needsAuthoritativeRecache == needsRecache)
        #expect(outcome.shouldSuppressAutomaticMovesDuringRecache == suppressesMoves)
        #expect(outcome.shouldSuppressSavedOrderPersistenceDuringRecache == suppressesPersistence)
    }

    @Test("The cache snapshot owns the first move's preflight")
    func firstMoveUsesInitialPreflight() {
        let state = State()
        var initialPreflightCalls = 0

        let shouldBegin = state.shouldBeginMove(
            currentTimestamp: initialTimestamp,
            initialPreflight: {
                initialPreflightCalls += 1
                return false
            }
        )

        #expect(!shouldBegin)
        #expect(initialPreflightCalls == 1)
    }

    @Test("A batch adopts its own move timestamp for the next item")
    func ownedTimestampAllowsNextItem() {
        var state = State()
        let ownedTimestamp = initialTimestamp.advanced(by: .milliseconds(1))
        state.recordMoveGateExit(timestamp: ownedTimestamp)
        var initialPreflightCalls = 0

        let shouldBegin = state.shouldBeginMove(
            currentTimestamp: ownedTimestamp,
            initialPreflight: {
                initialPreflightCalls += 1
                return false
            }
        )

        #expect(shouldBegin)
        #expect(initialPreflightCalls == 0)
    }

    @Test("A user timestamp between batch items supersedes the remainder")
    func interveningUserTimestampStopsBatch() {
        var state = State()
        let ownedTimestamp = initialTimestamp.advanced(by: .milliseconds(1))
        let userTimestamp = initialTimestamp.advanced(by: .milliseconds(2))
        state.recordMoveGateExit(timestamp: ownedTimestamp)

        #expect(!state.shouldBeginMove(
            currentTimestamp: userTimestamp,
            initialPreflight: { true }
        ))
    }

    @Test("Each owned item advances the batch timestamp")
    func successiveOwnedMovesAdvanceTimestamp() {
        var state = State()
        let firstMoveTimestamp = initialTimestamp.advanced(by: .milliseconds(1))
        let secondMoveTimestamp = initialTimestamp.advanced(by: .milliseconds(2))

        state.recordMoveGateExit(timestamp: firstMoveTimestamp)
        #expect(state.shouldBeginMove(
            currentTimestamp: firstMoveTimestamp,
            initialPreflight: { false }
        ))

        state.recordMoveGateExit(timestamp: secondMoveTimestamp)
        #expect(state.shouldBeginMove(
            currentTimestamp: secondMoveTimestamp,
            initialPreflight: { false }
        ))
        #expect(!state.shouldBeginMove(
            currentTimestamp: firstMoveTimestamp,
            initialPreflight: { true }
        ))
    }
}
