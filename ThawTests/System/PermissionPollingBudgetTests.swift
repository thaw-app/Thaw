//
//  PermissionPollingBudgetTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import Testing
@testable import Thaw

/// Characterization for the ungranted-poll budget on Permission: a
/// permission the user has declined must stop waking on a timer after a
/// bounded run of "no" answers, a grant on any tick must stop the poll for
/// good, and a poll spent to its budget must re-arm only through
/// Permission.resumePollingIfNeeded(), never on its own. The first
/// check runs inside configureCancellables, before the subscription
/// exists, so the budget accounting below always starts one tick in.
@Suite("Permission ungranted-poll budget")
@MainActor
struct PermissionPollingBudgetTests {
    /// Answers whatever granted holds and counts every read.
    private final class CheckStub {
        var granted = false
        var readCount = 0
    }

    private func makePermission(
        stub: CheckStub,
        budget: Int,
        request: @escaping (@escaping @MainActor @Sendable (Bool, Bool) -> Void) -> Void = { _ in }
    ) -> Permission {
        Permission(
            title: "Test Permission",
            iconName: "star",
            iconColor: .blue,
            details: [],
            isRequired: true,
            settingsURL: nil,
            check: {
                stub.readCount += 1
                return stub.granted
            },
            request: request,
            pollInterval: 3,
            ungrantedPollBudget: budget
        )
    }

    @Test("a granted permission never arms the poll")
    func grantedNeverPolls() {
        let stub = CheckStub()
        stub.granted = true
        let permission = makePermission(stub: stub, budget: 10)
        #expect(permission.hasPermission)
        #expect(!permission.isPolling)
    }

    @Test("the poll stops itself once the ungranted budget is spent")
    func budgetStopsThePoll() {
        let stub = CheckStub()
        // The immediate first tick in init already counts, so a budget of
        // 3 leaves two driven ticks before the poll must stop.
        let permission = makePermission(stub: stub, budget: 3)
        #expect(permission.isPolling)

        permission.handlePollTick()
        #expect(permission.isPolling)

        permission.handlePollTick()
        #expect(!permission.isPolling)
    }

    @Test("a grant on any tick stops the poll and publishes the transition")
    func grantOnTickStopsThePoll() {
        let stub = CheckStub()
        let permission = makePermission(stub: stub, budget: 10)
        #expect(permission.isPolling)

        stub.granted = true
        permission.handlePollTick()
        #expect(permission.hasPermission)
        #expect(!permission.isPolling)
    }

    @Test("a late grant is caught after the budget via resume")
    func resumeCatchesLateGrant() {
        let stub = CheckStub()
        let permission = makePermission(stub: stub, budget: 1)
        // Budget 1 is spent by the immediate first check inside
        // configureCancellables.
        #expect(!permission.isPolling)

        stub.granted = true
        permission.resumePollingIfNeeded()
        // Resume's immediate check catches the grant, publishes it, and
        // leaves nothing armed.
        #expect(permission.hasPermission)
        #expect(!permission.isPolling)
    }

    @Test("a prompt still unanswered on the next tick becomes a decline")
    func unansweredPromptBecomesDecline() {
        let stub = CheckStub()
        // Ungranted requests report prompted, as both system prompts return at once.
        let permission = makePermission(stub: stub, budget: 10) { completion in completion(false, true) }
        permission.performRequest()
        #expect(!permission.wasDeclined)

        permission.handlePollTick()
        #expect(permission.wasDeclined)
        #expect(permission.isPolling)
    }

    @Test("resume does not re-arm a granted permission")
    func resumeSkipsGranted() {
        let stub = CheckStub()
        stub.granted = true
        let permission = makePermission(stub: stub, budget: 10)
        permission.resumePollingIfNeeded()
        #expect(!permission.isPolling)
    }
}
