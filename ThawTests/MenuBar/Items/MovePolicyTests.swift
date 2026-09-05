//
//  MovePolicyTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Characterizes `MenuBarItemManager.MovePolicy`, the pure decision core of
/// `move(item:to:)`: each attempt's observation is folded into the running
/// state and answered with retry, succeed, or a named stop reason. The
/// sequences below are the ones the field logs contain, replayed without a
/// menu bar.
@Suite("Move policy")
struct MovePolicyTests {
    typealias Policy = MenuBarItemManager.MovePolicy

    private func configuration(
        maxAttempts: Int = 8,
        itemIsControlItem: Bool = false,
        ownerHasSilentRecord: Bool = false
    ) -> Policy.Configuration {
        Policy.Configuration(
            maxAttempts: maxAttempts,
            displayWidth: 1728,
            itemIsControlItem: itemIsControlItem,
            ownerHasSilentRecord: ownerHasSilentRecord
        )
    }

    /// Runs `observations` through the policy and returns every decision.
    private func decisions(
        _ observations: [Policy.Observation],
        plannedTargetMinX: CGFloat? = -3725,
        configuration: Policy.Configuration? = nil
    ) -> [Policy.Decision] {
        var state = Policy.State(plannedTargetMinX: plannedTargetMinX)
        let configuration = configuration ?? self.configuration()
        return observations.map { Policy.decide(after: $0, state: &state, configuration: configuration) }
    }

    // MARK: Landing

    @Test("A verified landing succeeds on the first attempt")
    func landingSucceeds() {
        #expect(decisions([.landed]) == [.succeed])
    }

    @Test("A warm-up nudge followed by a landing succeeds on the second attempt")
    func warmUpThenLanding() {
        let displaced = Policy.Observation.displaced(revertedToStart: false, targetMinX: -3725)
        #expect(decisions([displaced, .landed]) == [.retry, .succeed])
    }

    // MARK: Refusal

    /// The 13:28:55 drag: the item followed the press into the notch and the
    /// release put it back at 1433 twice. Two reverts prove the refusal; one
    /// is the warm-up press #881 documents.
    @Test("Two consecutive reverted releases stop the move as refused")
    func twoRevertsAreARefusal() {
        let reverted = Policy.Observation.displaced(revertedToStart: true, targetMinX: -3725)
        #expect(decisions([reverted, reverted]) == [.retry, .stop(.refusedByMacOS)])
    }

    @Test("A single reverted release is only a warm-up")
    func singleRevertIsNotARefusal() {
        let reverted = Policy.Observation.displaced(revertedToStart: true, targetMinX: -3725)
        let displaced = Policy.Observation.displaced(revertedToStart: false, targetMinX: -3725)
        #expect(decisions([reverted, displaced, reverted]) == [.retry, .retry, .retry])
    }

    // MARK: Target movement

    /// The #881 numbers: the target measured at -4222 on one attempt and at
    /// 794 on the next, on a bar far narrower than that swing.
    @Test("A target that crossed a display width stops the move as moved")
    func displayWidthSwingIsStale() {
        let displaced = Policy.Observation.displaced(revertedToStart: false, targetMinX: 794)
        #expect(decisions([displaced], plannedTargetMinX: -4222) == [.stop(.targetMoved)])
    }

    /// The #924/#927 sequence: an anchor driven from 1682 to 1650 over the
    /// attempts while the item never landed.
    @Test("A target retreating on every attempt stops the move as retreating")
    func retreatingTargetIsCaught() {
        let steps: [CGFloat] = [1677, 1664, 1653]
        let observations = steps.map { Policy.Observation.displaced(revertedToStart: false, targetMinX: $0) }
        #expect(decisions(observations, plannedTargetMinX: 1682) == [.retry, .retry, .stop(.targetRetreating)])
    }

    @Test("A jittering target is reflow, not a retreat")
    func jitteringTargetKeepsRetrying() {
        let steps: [CGFloat] = [1677, 1684, 1679, 1686]
        let observations = steps.map { Policy.Observation.displaced(revertedToStart: false, targetMinX: $0) }
        #expect(decisions(observations, plannedTargetMinX: 1682).allSatisfy { $0 == .retry })
    }

    // MARK: Budget

    @Test("Displacing without landing spends the whole budget, then stops exhausted")
    func budgetExhaustion() {
        let displaced = Policy.Observation.displaced(revertedToStart: false, targetMinX: -3725)
        let result = decisions(Array(repeating: displaced, count: 3), configuration: configuration(maxAttempts: 3))
        #expect(result == [.retry, .retry, .stop(.budgetExhausted)])
    }

    @Test("A budget of zero still allows one attempt")
    func zeroBudgetAllowsOneAttempt() {
        let displaced = Policy.Observation.displaced(revertedToStart: false, targetMinX: nil)
        #expect(decisions([displaced], configuration: configuration(maxAttempts: 0)) == [.stop(.budgetExhausted)])
    }

    // MARK: Failures

    @Test("Owner silence is retried until the budget runs out")
    func ownerSilenceRetries() {
        let silent = Policy.Observation.failed(.ownerSilent)
        let result = decisions(Array(repeating: silent, count: 2), configuration: configuration(maxAttempts: 2))
        #expect(result == [.retry, .stop(.ownerSilent)])
    }

    /// The 13:15:47 drag: the owner carried a standing unresponsive mark, so
    /// the first timeout ended the move at once.
    @Test("An owner with a silent record is not retried after another silence")
    func silentRecordStopsAtOnce() {
        let silent = Policy.Observation.failed(.ownerSilent)
        #expect(decisions([silent], configuration: configuration(ownerHasSilentRecord: true)) == [.stop(.ownerAlwaysSilent)])
    }

    @Test("A silent record does not shorten a move whose owner is answering")
    func silentRecordLeavesDisplacementsAlone() {
        let displaced = Policy.Observation.displaced(revertedToStart: false, targetMinX: -3725)
        #expect(decisions([displaced, .landed], configuration: configuration(ownerHasSilentRecord: true)) == [.retry, .succeed])
    }

    @Test("Definitive failures stop on the attempt they occur", arguments: [
        (Policy.AttemptFailure.itemGone, Policy.StopReason.itemGone),
        (.destinationGone, .destinationGone),
        (.ownerUnresponsive, .ownerUnresponsive),
        (.superseded, .superseded),
        (.overran, .overran),
        (.unsafePath, .unsafePath),
    ])
    func definitiveFailuresStop(failure: Policy.AttemptFailure, reason: Policy.StopReason) {
        #expect(decisions([.failed(failure)]) == [.stop(reason)])
    }

    @Test("Unclassified failures are retried, then stop as other")
    func otherFailuresRetry() {
        let other = Policy.Observation.failed(.other)
        #expect(decisions([other, other], configuration: configuration(maxAttempts: 2)) == [.retry, .stop(.other)])
    }

    // MARK: State

    @Test("Any displacement counts as events having succeeded")
    func displacementMarksEventsSucceeded() {
        var state = Policy.State(plannedTargetMinX: 100)
        _ = Policy.decide(
            after: .displaced(revertedToStart: false, targetMinX: 100),
            state: &state,
            configuration: configuration()
        )
        #expect(state.anyEventsSucceeded)
        #expect(state.attempts == 1)
        #expect(state.targetMinXHistory == [100, 100])
    }

    @Test("A failure leaves the events-succeeded flag alone")
    func failureLeavesEventsFlag() {
        var state = Policy.State(plannedTargetMinX: nil)
        _ = Policy.decide(after: .failed(.other), state: &state, configuration: configuration())
        #expect(!state.anyEventsSucceeded)
        #expect(state.latestTargetMinX == nil)
    }

    // MARK: Pre-attempt position match

    @Test("A position match is trusted on the first attempt")
    func firstAttemptMatchIsTrusted() {
        #expect(Policy.trustsPositionMatch(attempt: 1, anyEventsSucceeded: false, itemIsControlItem: true))
    }

    @Test("A retry's match on a control item needs observed displacement")
    func controlItemRetryNeedsDisplacement() {
        #expect(!Policy.trustsPositionMatch(attempt: 2, anyEventsSucceeded: false, itemIsControlItem: true))
        #expect(Policy.trustsPositionMatch(attempt: 2, anyEventsSucceeded: true, itemIsControlItem: true))
    }

    @Test("A retry's match on an ordinary item is always trusted")
    func ordinaryItemRetryIsTrusted() {
        #expect(Policy.trustsPositionMatch(attempt: 5, anyEventsSucceeded: false, itemIsControlItem: false))
    }

    // MARK: Deadlines

    @Test("Another attempt may start only inside the move deadline")
    func moveDeadline() {
        #expect(Policy.mayStartAnotherAttempt(elapsed: .seconds(7), deadline: .seconds(8)))
        #expect(!Policy.mayStartAnotherAttempt(elapsed: .seconds(8), deadline: .seconds(8)))
    }

    // MARK: Stop reasons

    @Test("Reasons that leave the item possibly landed get the final check", arguments: [
        Policy.StopReason.targetMoved, .targetRetreating, .ownerAlwaysSilent, .ownerSilent, .overran, .budgetExhausted, .other,
    ])
    func finalCheckReasons(reason: Policy.StopReason) {
        #expect(reason.deservesFinalLandingCheck)
    }

    @Test("Reasons that prove the item did not land skip the final check", arguments: [
        Policy.StopReason.refusedByMacOS, .ownerUnresponsive, .itemGone, .destinationGone, .superseded, .unsafePath,
    ])
    func noFinalCheckReasons(reason: Policy.StopReason) {
        #expect(!reason.deservesFinalLandingCheck)
    }

    @Test("Only silence is filed against the owner")
    func onlySilenceIsFiled() {
        let filed: [Policy.StopReason] = [.ownerUnresponsive, .ownerAlwaysSilent, .ownerSilent]
        let notFiled: [Policy.StopReason] = [.refusedByMacOS, .targetMoved, .targetRetreating, .itemGone, .destinationGone, .superseded, .overran, .unsafePath, .budgetExhausted, .other]
        let everyFiledReasonIsFiled = filed.allSatisfy(\.isFiledAgainstOwner)
        let noOtherReasonIsFiled = notFiled.allSatisfy { !$0.isFiledAgainstOwner }
        #expect(everyFiledReasonIsFiled)
        #expect(noOtherReasonIsFiled)
    }

    // MARK: Error mapping

    private func makeItem() -> MenuBarItem {
        .fixture(tag: .appItem(bundleID: "com.example.IconSwitcher", title: "Item-0"), windowID: 2314)
    }

    @Test("Attempt errors reduce to the failure the policy reasons about")
    func attemptFailureMapping() {
        let item = makeItem()
        #expect(Policy.attemptFailure(for: .itemResponseTimeout(item)) == .ownerSilent)
        #expect(Policy.attemptFailure(for: .eventOperationTimeout(item)) == .ownerSilent)
        #expect(Policy.attemptFailure(for: .ownerUnresponsive(item)) == .ownerUnresponsive)
        #expect(Policy.attemptFailure(for: .missingItemBounds(item)) == .itemGone)
        #expect(Policy.attemptFailure(for: .missingDestinationBounds(item)) == .destinationGone)
        #expect(Policy.attemptFailure(for: .staleDestination(item)) == .staleDestination)
        #expect(Policy.attemptFailure(for: .moveSuperseded(item)) == .superseded)
        #expect(Policy.attemptFailure(for: .moveTimedOut(item)) == .overran)
        #expect(Policy.attemptFailure(for: .unsafeMovePath(item)) == .unsafePath)
        #expect(Policy.attemptFailure(for: .cannotComplete) == .other)
    }

    @Test("Stop reasons throw the error callers already handle", arguments: [
        (Policy.StopReason.refusedByMacOS, "dropReverted"),
        (.targetMoved, "staleDestination"),
        (.targetRetreating, "staleDestination"),
        (.ownerUnresponsive, "ownerUnresponsive"),
        (.itemGone, "missingItemBounds"),
        (.destinationGone, "missingDestinationBounds"),
        (.staleDestination, "staleDestination"),
        (.superseded, "moveSuperseded"),
        (.overran, "moveTimedOut"),
        (.unsafePath, "unsafeMovePath"),
        (.budgetExhausted, "cannotComplete"),
        (.ownerSilent, "cannotComplete"),
        (.other, "cannotComplete"),
    ])
    func stopReasonErrors(reason: Policy.StopReason, expected: String) {
        let thrown = MenuBarItemManager.moveError(for: reason, item: makeItem(), lastError: nil)
        let description = String(describing: thrown)
        #expect(description.contains(expected), "\(reason.logString) threw \(description)")
    }

    /// Silence rethrows the attempt's own timeout, so the caller keeps
    /// seeing the error it saw before.
    @Test("Silence rethrows the attempt's own error")
    func silenceRethrowsTheAttemptError() {
        let item = makeItem()
        let last = MenuBarItemManager.EventError.itemResponseTimeout(item)
        let thrown = MenuBarItemManager.moveError(for: .ownerSilent, item: item, lastError: last)
        let description = String(describing: thrown)
        #expect(description.contains("itemResponseTimeout"))
    }
}
