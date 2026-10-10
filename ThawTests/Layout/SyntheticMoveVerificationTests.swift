//
//  SyntheticMoveVerificationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Synthetic move verification budget")
@MainActor
struct SyntheticMoveVerificationTests {
    @Test("An already landed move does not pay the settle delay")
    func immediateSuccess() async throws {
        var sleeps = 0
        let result = try await SyntheticMoveVerification.observe(
            budget: .milliseconds(250),
            now: { .zero },
            sleep: { _ in sleeps += 1 },
            snapshot: { 42 },
            isSatisfied: { $0 == 42 }
        )
        #expect(result.satisfied)
        #expect(result.value == 42)
        #expect(sleeps == 0)
    }

    @Test("Delayed success ends verification before the full budget")
    func delayedSuccess() async throws {
        var time: Duration = .zero
        var observations = 0
        let result = try await SyntheticMoveVerification.observe(
            budget: .milliseconds(250),
            now: { time },
            sleep: { time += $0 },
            snapshot: { observations += 1; return observations },
            isSatisfied: { $0 == 2 }
        )
        #expect(result.satisfied)
        #expect(observations == 2)
        #expect(time == .milliseconds(125))
    }

    @Test("An ignored move has bounded walks and returns the final snapshot")
    func noMovement() async throws {
        var time: Duration = .zero
        var observations = 0
        let result = try await SyntheticMoveVerification.observe(
            budget: .milliseconds(250),
            now: { time },
            sleep: { time += $0 },
            snapshot: { observations += 1; return observations },
            isSatisfied: { _ in false }
        )
        #expect(!result.satisfied)
        #expect(result.value == 3)
        #expect(observations == 3)
        #expect(time == .milliseconds(250))
    }

    @Test("Slow enumeration consumes the wait budget, without another AX walk")
    func slowEnumeration() async throws {
        var time: Duration = .zero
        var observations = 0
        let result = try await SyntheticMoveVerification.observe(
            budget: .milliseconds(250),
            now: { time },
            sleep: { _ in Issue.record("No further wait after a slow AX walk") },
            snapshot: {
                observations += 1
                time += .milliseconds(400)
                return observations
            },
            isSatisfied: { _ in false }
        )
        #expect(!result.satisfied)
        #expect(observations == 1)
    }

    @Test("Cancellation stops polling rather than triggering another attempt")
    func cancellation() async {
        var observations = 0
        await #expect(throws: CancellationError.self) {
            _ = try await SyntheticMoveVerification.observe(
                budget: .milliseconds(250),
                now: { .zero },
                sleep: { _ in throw CancellationError() },
                snapshot: { observations += 1; return false },
                isSatisfied: { $0 }
            )
        }
        #expect(observations == 1)
    }
}
