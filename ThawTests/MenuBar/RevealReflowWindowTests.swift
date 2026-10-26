//
//  RevealReflowWindowTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// The bar counts as reflowing for a short window after the revealed section changes.
@MainActor
@Suite("Reveal reflow window")
struct RevealReflowWindowTests {
    /// A clock the test moves by hand.
    private final class ManualClock {
        var now = Date(timeIntervalSinceReferenceDate: 1000)
    }

    @Test("With no transition seen the bar is settled")
    func settledBeforeAnyTransition() {
        let clock = ManualClock()
        let window = RevealReflowWindow(now: { clock.now })

        #expect(!window.isSettling)
    }

    @Test("A revealed-section change opens the window, which closes once it has passed")
    func changeOpensTheWindow() {
        let clock = ManualClock()
        let window = RevealReflowWindow(now: { clock.now })
        let revealed = CurrentValueSubject<MenuBarSectionName?, Never>(nil)
        window.observe(revealed.eraseToAnyPublisher())

        revealed.send(.hidden)
        #expect(window.isSettling)

        clock.now += RevealReflowWindow.settleWindow - 0.01
        #expect(window.isSettling)

        clock.now += 0.02
        #expect(!window.isSettling)
    }

    @Test("A hide opens the window too")
    func hideOpensTheWindow() {
        let clock = ManualClock()
        let window = RevealReflowWindow(now: { clock.now })
        let revealed = CurrentValueSubject<MenuBarSectionName?, Never>(.hidden)
        window.observe(revealed.eraseToAnyPublisher())

        revealed.send(nil)

        #expect(window.isSettling)
    }

    @Test("The value the publisher holds when observed is not a transition")
    func currentValueIsNotATransition() {
        let clock = ManualClock()
        let window = RevealReflowWindow(now: { clock.now })
        let revealed = CurrentValueSubject<MenuBarSectionName?, Never>(nil)

        window.observe(revealed.eraseToAnyPublisher())

        #expect(!window.isSettling)
    }

    @Test("The change is seen as it is made, so the window opens at the change itself")
    func changeIsSeenSynchronously() {
        let clock = ManualClock()
        let window = RevealReflowWindow(now: { clock.now })
        let revealed = CurrentValueSubject<MenuBarSectionName?, Never>(nil)
        window.observe(revealed.eraseToAnyPublisher())
        let changedAt = clock.now

        revealed.send(.alwaysHidden)
        clock.now = changedAt + RevealReflowWindow.settleWindow

        #expect(!window.isSettling)
    }

    @Test("A later change restarts the window")
    func laterChangeRestarts() {
        let clock = ManualClock()
        let window = RevealReflowWindow(now: { clock.now })
        let revealed = CurrentValueSubject<MenuBarSectionName?, Never>(nil)
        window.observe(revealed.eraseToAnyPublisher())

        revealed.send(.hidden)
        clock.now += RevealReflowWindow.settleWindow - 0.1
        revealed.send(nil)
        clock.now += 0.2

        #expect(window.isSettling)
    }

    @Test("Observing a new publisher drops the old one")
    func observingReplaces() {
        let clock = ManualClock()
        let window = RevealReflowWindow(now: { clock.now })
        let old = PassthroughSubject<MenuBarSectionName?, Never>()
        let new = PassthroughSubject<MenuBarSectionName?, Never>()
        window.observe(old.eraseToAnyPublisher())
        window.observe(new.eraseToAnyPublisher())

        // The first value from each publisher is the current one, not a change.
        old.send(nil)
        old.send(.hidden)
        #expect(!window.isSettling)

        new.send(nil)
        new.send(.hidden)
        #expect(window.isSettling)
    }

    @Test("The window is open strictly before its length has passed", arguments: [
        (0.0, true),
        (0.49, true),
        (0.5, false),
        (2.0, false),
    ])
    func decision(elapsed: TimeInterval, settling: Bool) {
        let last = Date(timeIntervalSinceReferenceDate: 0)

        #expect(RevealReflowWindow.isSettling(lastTransition: last, now: last + elapsed) == settling)
        #expect(!RevealReflowWindow.isSettling(lastTransition: nil, now: last + elapsed))
    }

    @Test("Before setup the manager offers a publisher that never emits, which is why the window observes after it")
    func managerPublisherIsEmptyBeforeSetup() {
        let manager = MenuBarManager()
        var received = 0
        let subscription = manager.revealedSectionChanges.sink { _ in received += 1 }
        defer { subscription.cancel() }

        #expect(received == 0)
        #expect(!manager.revealReflow.isSettling)
    }

    @Test("Inside the window the manager holds off the MenuBarAgent nudge, outside it does not")
    func managerGatesTheNudgeOnTheWindow() {
        let manager = MenuBarManager()
        #expect(!manager.shouldSuppressMenuBarAgentNudge)

        manager.revealReflow.noteTransition()

        #expect(manager.revealReflow.isSettling)
        #expect(manager.shouldSuppressMenuBarAgentNudge)
        // The gate returns before it reaches the status item, so this touches nothing.
        #expect(!manager.requestMenuBarAgentPositionRefresh())
    }

    @Test("The transition flag still holds the nudge off on its own")
    func transitionFlagAloneSuppresses() {
        let manager = MenuBarManager()

        manager.setRevealHideTransitionActive(true)
        defer { manager.setRevealHideTransitionActive(false) }

        #expect(!manager.revealReflow.isSettling)
        #expect(manager.shouldSuppressMenuBarAgentNudge)
    }
}
