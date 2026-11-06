//
//  BarSettlingHoldTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// The clocks that hold a purpose off after the bar was disturbed: the quiet period after a wake, a
/// display invalidation or a shift, the reflow window after a reveal, and the kit's transition flag.
@MainActor
@Suite("Bar settling holds")
struct BarSettlingHoldTests {
    private let clock = TestClock()

    private func makeSettling() -> BarSettling {
        let clock = clock
        return BarSettling(now: { clock.now })
    }

    // MARK: Quiet period

    @Test("An undisturbed bar is quiet")
    func quietBeforeAnyDisturbance() {
        #expect(makeSettling().isBarQuiet())
    }

    @Test("A wake, display invalidation or shift starts the quiet period", arguments: [
        BarSettling.Disturbance.screensWoke, .displaysInvalidated, .barLayoutShifted,
    ])
    func disturbanceStartsTheQuietPeriod(disturbance: BarSettling.Disturbance) {
        let settling = makeSettling()

        settling.note(disturbance)
        clock.now += BarSettling.quietPeriod - .milliseconds(500)
        #expect(!settling.isBarQuiet())

        clock.now += .seconds(1)
        #expect(settling.isBarQuiet())
        #expect(!settling.isSettling, "a clock disturbance starts no settle")
    }

    @Test("A later instant passed in holds the bar too")
    func extraInstantHolds() {
        let settling = makeSettling()
        let restrictionChange = clock.now

        clock.now += .seconds(1)
        #expect(!settling.isBarQuiet(alsoAfter: restrictionChange))
        #expect(settling.isBarQuiet())

        clock.now += BarSettling.quietPeriod
        #expect(settling.isBarQuiet(alsoAfter: restrictionChange))
    }

    @Test("The quiet rule on its own")
    func quietRule() {
        let start = ContinuousClock.now
        func at(_ seconds: Int) -> ContinuousClock.Instant {
            start + .seconds(seconds)
        }

        #expect(BarSettling.isQuiet(now: at(10), events: [nil, at(2)], quietPeriod: .seconds(5)))
        #expect(!BarSettling.isQuiet(now: at(10), events: [at(2), at(8)], quietPeriod: .seconds(5)))
        #expect(BarSettling.isQuiet(now: at(10), events: [], quietPeriod: .seconds(5)))
    }

    // MARK: Agent nudge

    @Test("With no reveal seen the nudge may go ahead")
    func nudgeFreeBeforeAnyReveal() {
        #expect(makeSettling().hold(for: .agentNudge) == nil)
    }

    @Test("A revealed-section change holds the nudge until the reflow window has passed")
    func revealChangeHoldsTheNudge() {
        let settling = makeSettling()

        settling.note(.revealedSectionChanged)
        #expect(settling.hold(for: .agentNudge) == .revealReflow)

        clock.now += BarSettling.revealReflowWindow - .milliseconds(10)
        #expect(settling.hold(for: .agentNudge) == .revealReflow)

        clock.now += .milliseconds(20)
        #expect(settling.hold(for: .agentNudge) == nil)
    }

    @Test("A later change restarts the reflow window")
    func laterChangeRestarts() {
        let settling = makeSettling()

        settling.note(.revealedSectionChanged)
        clock.now += BarSettling.revealReflowWindow - .milliseconds(100)
        settling.note(.revealedSectionChanged)
        clock.now += .milliseconds(200)

        #expect(settling.hold(for: .agentNudge) == .revealReflow)
    }

    @Test("The window is open strictly before its length has passed", arguments: [
        (Duration.zero, true),
        (.milliseconds(490), true),
        (.milliseconds(500), false),
        (.seconds(2), false),
    ])
    func reflowDecision(elapsed: Duration, reflowing: Bool) {
        let last = ContinuousClock.now

        #expect(BarSettling.isReflowing(lastRevealChange: last, now: last + elapsed) == reflowing)
        #expect(!BarSettling.isReflowing(lastRevealChange: nil, now: last + elapsed))
    }

    @Test("The kit's transition flag holds the nudge on its own, and only while set")
    func transitionHoldsTheNudge() {
        let settling = makeSettling()

        settling.note(.revealTransition(active: true))
        #expect(settling.isRevealTransitionActive)
        #expect(settling.hold(for: .agentNudge) == .revealTransition)

        settling.note(.revealTransition(active: false))
        #expect(!settling.isRevealTransitionActive)
        #expect(settling.hold(for: .agentNudge) == nil)
    }

    @Test("The reflow window is reported first when both hold the nudge")
    func reflowReportedFirst() {
        let settling = makeSettling()

        settling.note(.revealTransition(active: true))
        settling.note(.revealedSectionChanged)

        #expect(settling.hold(for: .agentNudge) == .revealReflow)
    }

    // MARK: Observers

    @Test("A revealed-section change is reported as it is made, and the current value is not a change")
    func observerReportsChanges() {
        let settling = makeSettling()
        let observers = BarSettlingObservers(settling: settling, observesScreenWakes: false)
        let revealed = CurrentValueSubject<MenuBarSectionName?, Never>(nil)
        observers.observe(revealedSections: revealed.eraseToAnyPublisher())
        #expect(settling.hold(for: .agentNudge) == nil)

        revealed.send(.hidden)
        #expect(settling.hold(for: .agentNudge) == .revealReflow)
        clock.now += BarSettling.revealReflowWindow
        revealed.send(nil)

        #expect(settling.hold(for: .agentNudge) == .revealReflow, "a hide opens the window too")
    }

    @Test("Observing a new reveal publisher drops the old one")
    func observingReplaces() {
        let settling = makeSettling()
        let observers = BarSettlingObservers(settling: settling, observesScreenWakes: false)
        let old = PassthroughSubject<MenuBarSectionName?, Never>()
        let new = PassthroughSubject<MenuBarSectionName?, Never>()
        observers.observe(revealedSections: old.eraseToAnyPublisher())
        observers.observe(revealedSections: new.eraseToAnyPublisher())

        // The first value from each publisher is the current one, not a change.
        old.send(nil)
        old.send(.hidden)
        #expect(settling.hold(for: .agentNudge) == nil)

        new.send(nil)
        new.send(.hidden)
        #expect(settling.hold(for: .agentNudge) == .revealReflow)
    }

    @Test("A display invalidation is reported as a disturbance")
    func observerReportsDisplayInvalidations() {
        let settling = makeSettling()
        let observers = BarSettlingObservers(settling: settling, observesScreenWakes: false)
        let invalidations = PassthroughSubject<Void, Never>()
        observers.observe(displayInvalidations: invalidations)

        invalidations.send()

        #expect(!settling.isBarQuiet())
    }

    // MARK: Menu bar manager

    @Test("Before setup the manager offers a reveal publisher that never emits")
    func managerPublisherIsEmptyBeforeSetup() {
        let manager = MenuBarManager()
        var received = 0
        let subscription = manager.revealedSectionChanges.sink { _ in received += 1 }
        defer { subscription.cancel() }

        #expect(received == 0)
        #expect(!manager.shouldSuppressMenuBarAgentNudge)
    }

    @Test("Inside the reflow window the manager holds off the MenuBarAgent nudge")
    func managerGatesTheNudgeOnTheWindow() {
        let manager = MenuBarManager(barSettling: makeSettling())
        #expect(!manager.shouldSuppressMenuBarAgentNudge)

        manager.barSettling.note(.revealedSectionChanged)

        #expect(manager.shouldSuppressMenuBarAgentNudge)
        // The gate returns before it reaches the status item, so this touches nothing.
        #expect(!manager.requestMenuBarAgentPositionRefresh())
    }

    @Test("The kit's transition flag set through the manager holds the nudge off")
    func managerTransitionFlag() {
        let manager = MenuBarManager(barSettling: makeSettling())

        manager.setRevealHideTransitionActive(true)
        #expect(manager.isRevealHideTransitionActive)
        #expect(manager.shouldSuppressMenuBarAgentNudge)

        manager.setRevealHideTransitionActive(false)
        #expect(!manager.shouldSuppressMenuBarAgentNudge)
    }
}

// MARK: - Restriction, native bar and Thaw's own press

@MainActor
@Suite("Bar settling restriction and native bar holds")
struct BarSettlingRestrictionHoldTests {
    private let clock = TestClock()

    private func makeSettling() -> BarSettling {
        let clock = clock
        return BarSettling(now: { clock.now })
    }

    @Test("A restriction change holds automatic reorders for the reflow window")
    func restrictionHoldsReorders() {
        let settling = makeSettling()
        #expect(settling.hold(for: .layoutReorder) == nil)

        settling.note(.restrictionChanged)
        #expect(settling.hold(for: .layoutReorder) == .restrictionReflow)

        clock.now += BarSettling.restrictionReflowWindow - .milliseconds(10)
        #expect(settling.hold(for: .layoutReorder) == .restrictionReflow)

        clock.now += .milliseconds(10)
        #expect(settling.hold(for: .layoutReorder) == nil)
    }

    @Test("A restriction change holds the saved-order mirror for the quiet period, not the settle's quiet check")
    func restrictionHoldsTheMirror() {
        let settling = makeSettling()

        settling.note(.restrictionChanged)
        #expect(settling.hold(for: .savedOrderMirror) == .barNotQuiet)
        #expect(settling.isBarQuiet(), "a display settle waits on wakes and shifts only")

        clock.now += BarSettling.quietPeriod
        #expect(settling.hold(for: .savedOrderMirror) == nil)
    }

    @Test("A wake holds the saved-order mirror")
    func wakeHoldsTheMirror() {
        let settling = makeSettling()

        settling.note(.screensWoke)

        #expect(settling.hold(for: .savedOrderMirror) == .barNotQuiet)
    }

    @Test("A native menu bar change holds bar mutations for its window")
    func nativeBarHoldsMutations() {
        let settling = makeSettling()
        #expect(settling.hold(for: .barMutation) == nil)

        settling.note(.nativeBarChanged)
        #expect(settling.hold(for: .barMutation) == .nativeBarChanging)

        clock.now += BarSettling.nativeBarChangeWindow
        #expect(settling.hold(for: .barMutation) == nil)
    }

    @Test("The first display change after Thaw's own press is Thaw's, once")
    func thawPressFlipIsUsedUp() {
        let settling = makeSettling()
        #expect(!settling.takeThawPressDisplayFlip())

        settling.note(.thawPressFlipsDisplay)

        #expect(settling.takeThawPressDisplayFlip())
        #expect(!settling.takeThawPressDisplayFlip())
    }

    @Test("A display change long after Thaw's press is the user's")
    func thawPressFlipExpires() {
        let settling = makeSettling()

        settling.note(.thawPressFlipsDisplay)
        clock.now += BarSettling.thawPressFlipWindow

        #expect(!settling.takeThawPressDisplayFlip())
    }

    @Test("None of these start a settle", arguments: [
        BarSettling.Disturbance.restrictionChanged, .nativeBarChanged, .thawPressFlipsDisplay,
    ])
    func clockDisturbancesStartNoSettle(disturbance: BarSettling.Disturbance) {
        let settling = makeSettling()

        settling.note(disturbance)

        #expect(!settling.isSettling)
        #expect(disturbance.kind == nil)
    }

    @Test("The manager's defer flag follows the native-bar hold")
    func managerDefersOnNativeBarChange() {
        let manager = MenuBarManager(barSettling: makeSettling())
        #expect(!manager.shouldDeferBarMutation)

        manager.barSettling.note(.nativeBarChanged)

        #expect(manager.shouldDeferBarMutation)
    }

    @Test("A restriction change reported to the item manager holds the resort signal")
    func managerRestrictionSignal() {
        let manager = MenuBarItemManager(barSettling: makeSettling())
        defer { manager.postRestrictionRepairTask?.cancel() }

        manager.noteRestrictionChange()

        #expect(ControlResortHold.Signal(of: manager).restrictionChangedAt == clock.now)
        #expect(manager.barSettling.hold(for: .layoutReorder) == .restrictionReflow)
    }
}
