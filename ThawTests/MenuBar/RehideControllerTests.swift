//
//  RehideControllerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// Stands in for the pointer, the clock and the sections, so each rehide runs without a menu bar.
@MainActor
private final class RehideWorld {
    var settings = RehideController.Settings(autoRehide: true, strategy: .smart, interval: 2)
    var menuOpen = false
    var pointerAwayFromBars = true
    var pointerOverFrontmostApp = true
    var spaceID = 1
    var now = ContinuousClock.now
    var sleeps: [Duration] = []
    var hiddenSectionHides = 0
    var everySectionHides = 0
    private var held: [CheckedContinuation<Void, Never>] = []

    lazy var controller = RehideController(environment: RehideController.Environment(
        settings: { [unowned self] in settings },
        isAnyMenuOpen: { [unowned self] in menuOpen },
        isPointerAwayFromBars: { [unowned self] in pointerAwayFromBars },
        activeSpaceID: { [unowned self] in spaceID },
        isPointerOverFrontmostApp: { [unowned self] in pointerOverFrontmostApp },
        hideHiddenSection: { [unowned self] in hiddenSectionHides += 1 },
        hideEverySection: { [unowned self] in everySectionHides += 1 },
        now: { [unowned self] in now },
        sleep: { [unowned self] duration in
            sleeps.append(duration)
            await withCheckedContinuation { held.append($0) }
            try Task.checkCancellation()
        }
    ))

    /// Lets every queued rehide reach its wait.
    func settle() async {
        await mainActorQueueDrained()
    }

    /// Ends every wait and returns once the rehides have run to the end.
    func finishWaits() async {
        let waits = held
        held = []
        for wait in waits {
            wait.resume()
        }
        await controller.waitUntilIdle()
    }
}

@MainActor
@Suite("One rehide controller")
struct RehideControllerTests {
    @Test("A focus change hides the hidden section after the interval", arguments: [RehideStrategy.smart, .focusedApp])
    func focusChangeHides(strategy: RehideStrategy) async {
        let world = RehideWorld()
        world.settings.strategy = strategy
        world.controller.note(.focusChanged)
        await world.settle()
        #expect(world.sleeps == [.seconds(2)])
        await world.finishWaits()
        #expect(world.hiddenSectionHides == 1)
        #expect(world.everySectionHides == 0)
    }

    @Test("A focus change does nothing under the timed strategy, with rehide off, or with the pointer on a bar")
    func focusChangeIgnored() async {
        for change in [{ (world: RehideWorld) in world.settings.strategy = .timed },
                       { $0.settings.autoRehide = false },
                       { $0.pointerAwayFromBars = false }]
        {
            let world = RehideWorld()
            change(world)
            world.controller.note(.focusChanged)
            await world.settle()
            #expect(world.sleeps.isEmpty)
        }
    }

    @Test("A reveal while the focus rehide waits cancels it")
    func revealCancelsFocusRehide() async {
        let world = RehideWorld()
        world.controller.note(.focusChanged)
        await world.settle()
        world.controller.revealed()
        await world.finishWaits()
        #expect(world.hiddenSectionHides == 0)
    }

    @Test("A reveal less than half a second before the wait ends keeps the section, a later one does not")
    func revealGracePeriod() async {
        let world = RehideWorld()
        world.controller.revealed()
        world.controller.note(.focusChanged)
        await world.settle()
        world.now += .milliseconds(499)
        await world.finishWaits()
        #expect(world.hiddenSectionHides == 0)

        world.controller.note(.focusChanged)
        await world.settle()
        world.now += .milliseconds(1)
        await world.finishWaits()
        #expect(world.hiddenSectionHides == 1)
    }

    @Test("An open menu holds the focus rehide only under the smart strategy")
    func openMenuHoldsSmartFocusRehide() async {
        let world = RehideWorld()
        world.menuOpen = true
        world.controller.note(.focusChanged)
        await world.settle()
        await world.finishWaits()
        #expect(world.hiddenSectionHides == 0)

        world.settings.strategy = .focusedApp
        world.controller.note(.focusChanged)
        await world.settle()
        await world.finishWaits()
        #expect(world.hiddenSectionHides == 1)
    }

    @Test("A newer focus change replaces the waiting one")
    func newerFocusChangeWins() async {
        let world = RehideWorld()
        world.controller.note(.focusChanged)
        await world.settle()
        world.controller.note(.focusChanged)
        await world.settle()
        await world.finishWaits()
        #expect(world.sleeps.count == 2)
        #expect(world.hiddenSectionHides == 1)
    }

    @Test("An outside click under the smart strategy hides every section after the interval")
    func outsideClickHides() async {
        let world = RehideWorld()
        world.controller.note(.outsideClick { true })
        await world.settle()
        #expect(world.sleeps == [.seconds(2)])
        await world.finishWaits()
        #expect(world.everySectionHides == 1)
        #expect(world.hiddenSectionHides == 0)
    }

    @Test("Outside clicks are not checked unless smart rehide is on", arguments: [RehideStrategy.timed, .focusedApp])
    func outsideClickNeedsSmart(strategy: RehideStrategy) async {
        let world = RehideWorld()
        world.settings.strategy = strategy
        var checked = false
        world.controller.note(.outsideClick { checked = true; return true })
        world.settings = .init(autoRehide: false, strategy: .smart, interval: 2)
        world.controller.note(.outsideClick { checked = true; return true })
        await world.settle()
        #expect(!checked)
        #expect(world.sleeps.isEmpty)
    }

    @Test("A click that does not qualify arms nothing")
    func unqualifiedClick() async {
        let world = RehideWorld()
        world.controller.note(.outsideClick { false })
        await world.settle()
        #expect(world.sleeps.isEmpty)
    }

    @Test("A click that switched spaces hides even over another window or an open menu")
    func spaceChangeHides() async {
        let world = RehideWorld()
        world.menuOpen = true
        world.pointerOverFrontmostApp = false
        world.controller.note(.outsideClick { true })
        await world.settle()
        world.spaceID = 2
        await world.finishWaits()
        #expect(world.everySectionHides == 1)
    }

    @Test("An outside click keeps the sections when the pointer is not over the frontmost app or a menu is open")
    func outsideClickKept() async {
        for change in [{ (world: RehideWorld) in world.pointerOverFrontmostApp = false }, { $0.menuOpen = true }] {
            let world = RehideWorld()
            world.controller.note(.outsideClick { true })
            await world.settle()
            change(world)
            await world.finishWaits()
            #expect(world.everySectionHides == 0)
        }
    }

    @Test("A reveal from input cancels the outside-click rehide but a plain reveal does not")
    func inputRevealCancelsOutsideClick() async {
        let world = RehideWorld()
        world.controller.note(.outsideClick { true })
        await world.settle()
        world.controller.revealed()
        await world.finishWaits()
        #expect(world.everySectionHides == 1)

        world.controller.note(.outsideClick { true })
        await world.settle()
        world.controller.note(.inputReveal)
        await world.finishWaits()
        #expect(world.everySectionHides == 1)
    }

    @Test("The two rehides run side by side, so one click can arm both")
    func lanesAreIndependent() async {
        let world = RehideWorld()
        world.controller.note(.outsideClick { true })
        world.controller.note(.focusChanged)
        world.controller.note(.inputReveal)
        await world.settle()
        await world.finishWaits()
        #expect(world.hiddenSectionHides == 1)
        #expect(world.everySectionHides == 0)
    }
}

/// The live adapter on an app state that was never set up, so no section can show or hide.
@MainActor
@Suite("Live rehide environment", .serialized, .scratchDefaults)
struct LiveRehideEnvironmentTests {
    @Test("It reads the settings and answers every question without a set-up menu bar")
    func readsLiveState() async throws {
        let appState = AppState()
        appState.settings.general.rehideStrategy = .focusedApp
        appState.settings.general.rehideInterval = 7
        let environment = RehideController.Environment.live(appState: appState)
        let expected = RehideController.Settings(
            autoRehide: appState.settings.general.autoRehide,
            strategy: .focusedApp,
            interval: 7
        )
        #expect(environment.settings() == expected)
        _ = await environment.isAnyMenuOpen()
        _ = environment.isPointerAwayFromBars()
        #expect(environment.activeSpaceID() == environment.activeSpaceID())
        _ = environment.isPointerOverFrontmostApp()
        environment.hideHiddenSection()
        environment.hideEverySection()
        #expect(appState.menuBarManager.section(withName: .hidden)?.isHidden == true)
        let before = environment.now()
        try await environment.sleep(.zero)
        #expect(before <= environment.now())
    }

    @Test("The input manager forwards a reveal, which cancels a waiting outside-click rehide")
    func inputForwardsReveal() async {
        let appState = AppState()
        let world = RehideWorld()
        appState.hidEventManager.rehideController = world.controller
        world.controller.note(.outsideClick { true })
        await world.settle()
        #expect(world.sleeps == [.seconds(2)])

        appState.hidEventManager.cancelSmartRehide()
        await world.finishWaits()

        #expect(world.everySectionHides == 0)
    }

    @Test("An outside click before setup reaches the controller but arms nothing")
    func inputClickBeforeSetup() async throws {
        let appState = AppState()
        let world = RehideWorld()
        let input = appState.hidEventManager
        input.rehideController = world.controller
        let screen = try #require(NSScreen.screens.first)
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        input.handleSmartRehide(with: event, appState: appState, screen: screen)
        input.cancelSmartRehide()
        await world.settle()
        // Before setup no section is showing, so the click arms nothing.
        #expect(world.sleeps.isEmpty)
    }
}
