//
//  SectionTransitionSerializationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SectionTransitionSerializationTests {
    @Test("A second section pre-seat cannot change positions during the first verification")
    func preSeatWaitsForVerificationAndCommit() async throws {
        let gate = SimpleSemaphore(value: 1)
        let firstWritten = AsyncStream.makeStream(of: Void.self)
        let secondRequested = AsyncStream.makeStream(of: Void.self)
        var cleanShotWeight = 798
        var cleanShotAssigned = false
        var secondSawCommittedAssignment = false

        let cleanShot = Task {
            try await gate.withPermit {
                cleanShotWeight = 389
                firstWritten.continuation.yield(())
                firstWritten.continuation.finish()
                for await _ in secondRequested.stream {
                    break
                }
                #expect(cleanShotWeight == 389, "AdGuard must not re-space CleanShot before verification")
                cleanShotAssigned = true
            }
        }
        for await _ in firstWritten.stream {
            break
        }
        let adGuard = Task {
            secondRequested.continuation.yield(())
            secondRequested.continuation.finish()
            try await gate.withPermit {
                secondSawCommittedAssignment = cleanShotAssigned
                cleanShotWeight = 799
            }
        }
        try await cleanShot.value
        try await adGuard.value
        #expect(secondSawCommittedAssignment)
        #expect(cleanShotWeight == 799)
    }

    @Test("A failed move releases its permit for the next section transition")
    func failureReleasesPermit() async throws {
        enum MoveFailure: Error { case verification }
        let gate = SimpleSemaphore(value: 1)
        await #expect(throws: MoveFailure.verification) {
            try await gate.withPermit { throw MoveFailure.verification }
        }
        let committed = try await gate.withPermit { true }
        #expect(committed)
    }

    @Test("Cancellation during verification releases the permit without committing")
    func cancelledVerificationReleasesPermit() async throws {
        let gate = SimpleSemaphore(value: 1)
        let started = AsyncStream.makeStream(of: Void.self)
        let verification = AsyncStream.makeStream(of: Void.self)
        var committed = false
        let request = Task {
            try await gate.withPermit {
                started.continuation.yield(())
                started.continuation.finish()
                for await _ in verification.stream {
                    break
                }
                try Task.checkCancellation()
                committed = true
            }
        }
        for await _ in started.stream {
            break
        }
        request.cancel()
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(!committed)
        let nextCommitted = try await gate.withPermit { true }
        #expect(nextCommitted)
    }

    @Test("A cancelled request does not pre-seat or consume the active move's permit")
    func cancellationDoesNotMutate() async throws {
        let gate = SimpleSemaphore(value: 1)
        try await gate.wait()
        var wrotePositions = false
        let request = Task {
            try await gate.withPermit { wrotePositions = true }
        }
        request.cancel()
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(!wrotePositions)
        await gate.signal()
        let committed = try await gate.withPermit { true }
        #expect(committed)
    }
}
