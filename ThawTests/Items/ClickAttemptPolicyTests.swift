//
//  ClickAttemptPolicyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("A click gives each owner a fair number of attempts and reads a quiet press correctly")
struct ClickAttemptPolicyTests {
    private typealias AfterFailure = ClickAttemptPolicy.AfterFailure

    private static func rethrown(recordingOwner: Bool) -> AfterFailure {
        AfterFailure(retries: false, recordsUnresponsiveOwner: recordingOwner, reportsCannotComplete: false)
    }

    private static let cannotComplete = AfterFailure(
        retries: false, recordsUnresponsiveOwner: false, reportsCannotComplete: true
    )

    // MARK: Attempt budget

    @Test("A responsive owner gets every attempt the caller allows")
    func responsiveOwnerGetsTheCallersBudget() {
        #expect(ClickAttemptPolicy.attemptBudget(ownerUnresponsive: false, maxAttempts: 3) == 3)
        #expect(ClickAttemptPolicy.attemptBudget(ownerUnresponsive: false, maxAttempts: 1) == 1)
    }

    @Test("An owner known to ignore synthetic events gets one attempt, however many are allowed")
    func unresponsiveOwnerGetsOneAttempt() {
        #expect(ClickAttemptPolicy.attemptBudget(ownerUnresponsive: true, maxAttempts: 3) == 1)
        #expect(ClickAttemptPolicy.attemptBudget(ownerUnresponsive: true, maxAttempts: 10) == 1)
    }

    @Test("A caller asking for no attempts, or a negative number, still gets one")
    func budgetIsNeverBelowOne() {
        #expect(ClickAttemptPolicy.attemptBudget(ownerUnresponsive: false, maxAttempts: 0) == 1)
        #expect(ClickAttemptPolicy.attemptBudget(ownerUnresponsive: false, maxAttempts: -4) == 1)
    }

    // MARK: Press outcome

    @Test("A press the owner reacted to is done, whether or not the caller needs a reaction")
    func reactedPressIsOpened() {
        #expect(ClickAttemptPolicy.pressOutcome(didReact: true, requireObservedReaction: false) == .opened)
        #expect(ClickAttemptPolicy.pressOutcome(didReact: true, requireObservedReaction: true) == .opened)
    }

    @Test("A press with no reaction is returned as it is when the caller does not need one")
    func quietPressIsAcceptedWhenNoReactionIsRequired() {
        #expect(
            ClickAttemptPolicy.pressOutcome(didReact: false, requireObservedReaction: false)
                == .acceptWithoutReaction
        )
    }

    @Test("A press with no reaction falls back to a real click when the caller needs one")
    func quietPressPostsARealClickWhenAReactionIsRequired() {
        #expect(
            ClickAttemptPolicy.pressOutcome(didReact: false, requireObservedReaction: true)
                == .postRealClick
        )
    }

    // MARK: After a failed attempt

    @Test("An attempt that is not the last is retried, whatever the failure was")
    func earlierFailuresAreRetried() {
        let failures: [ClickAttemptPolicy.AttemptFailure] = [
            .event(indicatesUnresponsiveOwner: true),
            .event(indicatesUnresponsiveOwner: false),
            .other,
        ]
        for failure in failures {
            #expect(ClickAttemptPolicy.afterFailure(attempt: 1, budget: 3, failure: failure) == .retry)
            #expect(ClickAttemptPolicy.afterFailure(attempt: 2, budget: 3, failure: failure) == .retry)
        }
    }

    @Test("The last attempt's silent-owner failure is rethrown and marks the owner")
    func lastSilentOwnerFailureIsRecorded() {
        #expect(
            ClickAttemptPolicy.afterFailure(
                attempt: 3, budget: 3, failure: .event(indicatesUnresponsiveOwner: true)
            ) == Self.rethrown(recordingOwner: true)
        )
    }

    @Test("The last attempt's other event failure is rethrown without marking the owner")
    func lastUnrelatedEventFailureIsNotRecorded() {
        #expect(
            ClickAttemptPolicy.afterFailure(
                attempt: 3, budget: 3, failure: .event(indicatesUnresponsiveOwner: false)
            ) == Self.rethrown(recordingOwner: false)
        )
    }

    @Test("The last attempt's non-event failure is reported as the catch-all")
    func lastOtherFailureIsCannotComplete() {
        #expect(ClickAttemptPolicy.afterFailure(attempt: 3, budget: 3, failure: .other) == Self.cannotComplete)
    }

    @Test("With a budget of one, the first failure is already the last")
    func singleAttemptBudgetFailsAtOnce() {
        #expect(
            ClickAttemptPolicy.afterFailure(
                attempt: 1, budget: 1, failure: .event(indicatesUnresponsiveOwner: true)
            ) == Self.rethrown(recordingOwner: true)
        )
    }
}
