//
//  ClickTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
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

@MainActor
@Suite("Each item's click timeout is learned from how long its clicks took")
struct ClickTimeoutEstimatorTests {
    @Test("An item with no clicks on record gets the default")
    func unknownItemGetsTheDefault() {
        let estimator = ClickTimeoutEstimator<String>()

        #expect(estimator.timeout(for: "a") == .milliseconds(350))
        #expect(ClickTimeoutEstimator<String>.defaultTimeout == .milliseconds(350))
    }

    @Test("The first observation moves the estimate halfway from the default")
    func firstObservationBlendsWithTheDefault() {
        var estimator = ClickTimeoutEstimator<String>()

        let estimate = estimator.record(.milliseconds(550), for: "a")

        #expect(estimate == .milliseconds(450))
        #expect(estimator.timeout(for: "a") == .milliseconds(450))
    }

    @Test("Each later observation moves the estimate halfway again")
    func laterObservationsBlendWithTheEstimate() {
        var estimator = ClickTimeoutEstimator<String>()
        estimator.record(.milliseconds(550), for: "a")

        let estimate = estimator.record(.milliseconds(650), for: "a")

        #expect(estimate == .milliseconds(550))
    }

    @Test("A fast click cannot take the estimate below the floor")
    func clampsToTheFloor() {
        var estimator = ClickTimeoutEstimator<String>()

        let estimate = estimator.record(.milliseconds(10), for: "a")

        #expect(estimate == .milliseconds(200))
        #expect(estimator.timeout(for: "a") == .milliseconds(200))
    }

    @Test("A slow click cannot take the estimate above the ceiling")
    func clampsToTheCeiling() {
        var estimator = ClickTimeoutEstimator<String>()

        let estimate = estimator.record(.seconds(30), for: "a")

        #expect(estimate == .milliseconds(1000))
        #expect(estimator.timeout(for: "a") == .milliseconds(1000))
    }

    @Test("The next blend starts from the clamped estimate, not the raw observation")
    func blendsFromTheClampedEstimate() {
        var estimator = ClickTimeoutEstimator<String>()
        estimator.record(.seconds(30), for: "a")

        let estimate = estimator.record(.milliseconds(400), for: "a")

        #expect(estimate == .milliseconds(700))
    }

    @Test("Items learn separately")
    func itemsLearnSeparately() {
        var estimator = ClickTimeoutEstimator<String>()

        estimator.record(.milliseconds(950), for: "slow")

        #expect(estimator.timeout(for: "slow") == .milliseconds(650))
        #expect(estimator.timeout(for: "other") == .milliseconds(350))
    }

    @Test("Pruning forgets items that left and keeps the rest")
    func pruneForgetsDepartedItems() {
        var estimator = ClickTimeoutEstimator<String>()
        estimator.record(.milliseconds(950), for: "gone")
        estimator.record(.milliseconds(950), for: "here")

        estimator.prune(keeping: ["here"])

        #expect(estimator.timeout(for: "gone") == .milliseconds(350))
        #expect(estimator.timeout(for: "here") == .milliseconds(650))
    }
}

@MainActor
@Suite("Pointer handling around a synthetic click")
struct ClickPointerTests {
    private static let item = CGPoint(x: 1200, y: 12)
    private static let home = CGPoint(x: 400, y: 600)

    private struct Stopped: Error {}

    @MainActor
    private final class PointerLog {
        var events = [String]()

        func pointer(settle: @escaping () -> Void = {}) -> ClickPointer {
            ClickPointer(
                warp: { self.events.append("warp \(Int($0.x)),\(Int($0.y))") },
                hide: { self.events.append("hide") },
                show: { self.events.append("show") },
                settle: settle
            )
        }
    }

    @Test("A click cancelled while the pointer settles posts nothing and puts the pointer back")
    func cancelledDuringSettle() async {
        let log = PointerLog()
        let pointer = log.pointer(settle: { withUnsafeCurrentTask { $0?.cancel() } })
        let task = Task { @MainActor in
            try await MenuBarItemManager.withPointerParked(at: Self.item, restoringTo: Self.home, pointer: pointer) {
                log.events.append("click")
            }
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(log.events == ["warp 1200,12", "hide", "warp 400,600", "show"])
    }

    @Test("A failed click still puts the pointer back")
    func failedClickRestores() async {
        let log = PointerLog()
        await #expect(throws: Stopped.self) {
            try await MenuBarItemManager.withPointerParked(at: Self.item, restoringTo: Self.home, pointer: log.pointer()) {
                log.events.append("click")
                throw Stopped()
            }
        }
        #expect(log.events == ["warp 1200,12", "hide", "click", "warp 400,600", "show"])
    }
}

@Suite("Menu bar item direct presser")
struct MenuBarItemDirectPresserTests {
    @Test("The item's own element is pressed, whether its owner's or its source's")
    func ownElementIsPressable() {
        #expect(MenuBarItemDirectPresser.isPressable(elementPID: 990, for: [990]))
        // A hosted item's element is MenuBarAgent's.
        #expect(MenuBarItemDirectPresser.isPressable(elementPID: 786, for: [786, 990]))
    }

    @Test("A neighbour's element at the item's reported spot is not pressed")
    func neighbourIsNotPressable() {
        // One Switch reported where Window Manager was drawn.
        #expect(!MenuBarItemDirectPresser.isPressable(elementPID: 964, for: [990]))
    }

    @Test("An item with no known process presses nothing, since the element can't be checked")
    func unknownOwnerIsNotPressable() {
        #expect(!MenuBarItemDirectPresser.isPressable(elementPID: 964, for: [0]))
        #expect(!MenuBarItemDirectPresser.isPressable(elementPID: 964, for: []))
        #expect(!MenuBarItemDirectPresser.isPressable(elementPID: 0, for: [0]))
    }

    /// A menu-bar-only app relaunched gets new process IDs, and macOS posts no launch for it, so the
    /// cached item can still carry the old ones when it is clicked.
    @Test("The item's own app is pressed under a new process ID, and a neighbour still isn't")
    func relaunchedAppIsPressable() {
        #expect(MenuBarItemDirectPresser.isPressable(elementPID: 2001, for: [990], sameApp: true))
        #expect(!MenuBarItemDirectPresser.isPressable(elementPID: 964, for: [990], sameApp: false))
        #expect(!MenuBarItemDirectPresser.isPressable(elementPID: 0, for: [990], sameApp: true))
    }
}
