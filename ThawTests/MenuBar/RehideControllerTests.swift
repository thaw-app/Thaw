//
//  RehideControllerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
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
    var pointerInArea = false
    /// Answers given before falling back to pointerInArea and menuOpen, oldest first.
    var pointerInAreaAnswers: [Bool] = []
    var menuOpenAnswers: [Bool] = []
    var menuChecks = 0
    /// Holds this numbered menu check, counting from one, until finishWaits.
    var heldMenuCheck: Int?
    /// Lets a sleep move the clock and return at once instead of waiting for finishWaits.
    var sleepsReturnAtOnce = false
    var sectionHides: [MenuBarSection.Name] = []
    var monitorStarts: [MenuBarSection.Name] = []
    var moveHandlers: [MenuBarSection.Name: @MainActor () -> Void] = [:]
    private var held: [CheckedContinuation<Void, Never>] = []

    lazy var controller: RehideController = .init(environment: RehideController.Environment(
        settings: { [unowned self] in settings },
        isAnyMenuOpen: { [unowned self] in
            menuChecks += 1
            if menuChecks == heldMenuCheck {
                await withCheckedContinuation { held.append($0) }
            }
            return menuOpenAnswers.isEmpty ? menuOpen : menuOpenAnswers.removeFirst()
        },
        isPointerAwayFromBars: { [unowned self] in pointerAwayFromBars },
        activeSpaceID: { [unowned self] in spaceID },
        isPointerOverFrontmostApp: { [unowned self] in pointerOverFrontmostApp },
        hideHiddenSection: { [unowned self] in hiddenSectionHides += 1 },
        hideEverySection: { [unowned self] in everySectionHides += 1 },
        isPointerInActiveArea: { [unowned self] in
            pointerInAreaAnswers.isEmpty ? pointerInArea : pointerInAreaAnswers.removeFirst()
        },
        hideSection: { [unowned self] name in
            sectionHides.append(name)
            // MenuBarSection.hide reports back the same way.
            controller.hidden(name)
        },
        startPointerMonitor: { [unowned self] name, onMove in
            monitorStarts.append(name)
            moveHandlers[name] = onMove
        },
        stopPointerMonitor: { [unowned self] name in moveHandlers[name] = nil },
        now: { [unowned self] in now },
        sleep: { [unowned self] duration in
            sleeps.append(duration)
            if sleepsReturnAtOnce {
                now += duration
            } else {
                await withCheckedContinuation { held.append($0) }
            }
            try Task.checkCancellation()
        }
    ))

    func movePointer(over section: MenuBarSection.Name, inArea: Bool) {
        pointerInArea = inArea
        moveHandlers[section]?()
    }

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

    /// A hotkey reveal doesn't cancel an outside-click hide, so closing must.
    @Test("Closing the presentation drops a pending outside-click hide")
    func closingDropsOutsideClickRehide() async {
        let world = RehideWorld()
        world.controller.note(.outsideClick { true })
        await world.settle()
        world.controller.hidden(.hidden)
        world.controller.revealed()
        await world.finishWaits()
        #expect(world.everySectionHides == 0)
    }

    /// Disabling the preference while a focus or outside-click delay waits must prevent its hide.
    @Test("Disabling rehide stops a pending focus or outside-click hide", arguments: [false, true])
    func disablingStopsPendingHide(outside: Bool) async {
        let world = RehideWorld()
        if outside {
            world.controller.note(.outsideClick { true })
        } else {
            world.controller.note(.focusChanged)
        }
        await world.settle()
        world.settings.autoRehide = false

        await world.finishWaits()

        #expect(world.hiddenSectionHides == 0)
        #expect(world.everySectionHides == 0)
    }

    /// A menu answer can arrive after the user disabled automatic rehiding.
    @Test("Disabling rehide during a menu probe prevents the pending hide", arguments: [false, true])
    func disablingDuringMenuProbe(outside: Bool) async {
        let world = RehideWorld()
        world.sleepsReturnAtOnce = true
        world.heldMenuCheck = 1
        if outside {
            world.controller.note(.outsideClick { true })
        } else {
            world.controller.note(.focusChanged)
        }
        while world.menuChecks < 1 {
            await world.settle()
        }
        world.settings.autoRehide = false

        await world.finishWaits()
        await world.settle()

        #expect(world.hiddenSectionHides == 0)
        #expect(world.everySectionHides == 0)
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
        appState.settings.visibility.rehideStrategy = .focusedApp
        appState.settings.visibility.rehideInterval = 7
        let environment = RehideController.Environment.live(appState: appState)
        let expected = RehideController.Settings(
            autoRehide: appState.settings.visibility.autoRehide,
            strategy: .focusedApp,
            interval: 7
        )
        #expect(environment.settings() == expected)
        _ = await environment.isAnyMenuOpen()
        _ = environment.isPointerAwayFromBars()
        #expect(environment.activeSpaceID() == Bridging.getActiveSpaceID(), "it answers with the system's active Space")
        _ = environment.isPointerOverFrontmostApp()
        environment.hideHiddenSection()
        environment.hideEverySection()
        environment.hideSection(.alwaysHidden)
        _ = environment.isPointerInActiveArea()
        environment.startPointerMonitor(.hidden) {}
        environment.stopPointerMonitor(.hidden)
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
        // The click lands in a window of its own, which is never shown. A click with no window would
        // match the control item, which has none before setup, and be turned away as a click on that
        // item before the sections are asked.
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 10, height: 10), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        try #require(event.window === window)
        input.handleSmartRehide(with: event, appState: appState, screen: screen)
        await world.settle()
        // Before setup no section is showing, so the click arms nothing. The click is not cancelled
        // here: a cancelled rehide would also leave no sleep, whatever the click said.
        #expect(world.sleeps.isEmpty)

        // The same controller does arm for a click that qualifies, so the empty list above is the
        // click's own answer and not a controller that never listens.
        world.controller.note(.outsideClick { true })
        await world.settle()
        #expect(world.sleeps == [.seconds(2)])
        await world.finishWaits()
    }
}

@MainActor
@Suite("Section rehide timers")
struct SectionRehideTests {
    private static let poll = Duration.milliseconds(250)

    private func world(_ strategy: RehideStrategy, atOnce: Bool = true) -> RehideWorld {
        let world = RehideWorld()
        world.settings.strategy = strategy
        world.sleepsReturnAtOnce = atOnce
        return world
    }

    @Test("A timed reveal with no movement hides after a full interval of polls", arguments: [RehideStrategy.timed, .smart])
    func hidesAfterInterval(strategy: RehideStrategy) async {
        let world = world(strategy)
        world.controller.revealed(.hidden)
        await world.controller.waitUntilIdle()
        #expect(world.sleeps == Array(repeating: Self.poll, count: 8))
        #expect(world.sectionHides == [.hidden])
        #expect(world.monitorStarts == (strategy == .timed ? [.hidden] : []))
        #expect(world.moveHandlers.isEmpty)
    }

    @Test("Moving into a bar stops the timed countdown and leaving starts one, never two")
    func pointerDrivesCountdown() async {
        let world = world(.timed, atOnce: false)
        world.pointerInArea = true
        world.controller.revealed(.hidden)
        await world.settle()
        #expect(world.sleeps.isEmpty)
        world.movePointer(over: .hidden, inArea: false)
        world.movePointer(over: .hidden, inArea: false)
        await world.settle()
        #expect(world.sleeps.count == 1)
        world.movePointer(over: .hidden, inArea: true)
        await world.finishWaits()
        #expect(world.sectionHides.isEmpty)
    }

    @Test("A countdown the pointer ended still counts as running until a move inside the bar clears it")
    func endedCountdownNeedsAMoveInside() async {
        let world = world(.timed)
        world.pointerInAreaAnswers = [false, true]
        world.controller.revealed(.hidden)
        await world.controller.waitUntilIdle()
        world.movePointer(over: .hidden, inArea: false)
        await world.controller.waitUntilIdle()
        #expect(world.sleeps.count == 1)
        world.movePointer(over: .hidden, inArea: true)
        world.movePointer(over: .hidden, inArea: false)
        await world.controller.waitUntilIdle()
        #expect(world.sectionHides == [.hidden])
    }

    @Test("An open menu while waiting starts the interval over")
    func openMenuResetsInterval() async {
        let world = world(.timed)
        world.menuOpenAnswers = [true, true, true, true]
        world.controller.revealed(.hidden)
        await world.controller.waitUntilIdle()
        #expect(world.sleeps.count == 12)
        #expect(world.sectionHides == [.hidden])
    }

    @Test("A menu open at the end restarts the countdown, and only smart restarts the whole check", arguments: [RehideStrategy.timed, .smart])
    func openMenuAtEndRestarts(strategy: RehideStrategy) async {
        let world = world(strategy)
        world.menuOpenAnswers = Array(repeating: false, count: 8) + [true]
        world.controller.revealed(.hidden)
        await world.controller.waitUntilIdle()
        await world.controller.waitUntilIdle()
        #expect(world.sleeps.count == 16)
        #expect(world.sectionHides == [.hidden])
        #expect(world.monitorStarts.count == (strategy == .timed ? 1 : 0))
    }

    @Test("A pointer back in the bar at the end restarts the timed checks with a fresh monitor")
    func pointerAtEndRestarts() async {
        let world = world(.timed)
        world.pointerInAreaAnswers = Array(repeating: false, count: 9) + [true]
        world.controller.revealed(.hidden)
        await world.controller.waitUntilIdle()
        await world.controller.waitUntilIdle()
        #expect(world.monitorStarts == [.hidden, .hidden])
        #expect(world.sleeps.count == 16)
        #expect(world.sectionHides == [.hidden])
    }

    @Test("A countdown cancelled while it asks about open menus neither hides nor restarts", arguments: [false, true])
    func cancelDuringMenuCheck(menuOpen: Bool) async {
        let world = world(.timed)
        world.heldMenuCheck = 9
        world.controller.revealed(.hidden)
        while world.menuChecks < 9 {
            await world.settle()
        }
        world.movePointer(over: .hidden, inArea: true)
        world.menuOpen = menuOpen
        await world.finishWaits()
        await world.settle()
        await world.controller.waitUntilIdle()
        #expect(world.sectionHides.isEmpty)
        #expect(world.sleeps.count == 8)
    }

    @Test("The smart fallback gives up for good once the pointer reaches a bar")
    func smartFallbackEndsInBar() async {
        let world = world(.smart)
        world.pointerInAreaAnswers = [true]
        world.controller.revealed(.hidden)
        await world.controller.waitUntilIdle()
        #expect(world.sleeps == [Self.poll])
        #expect(world.sectionHides.isEmpty)
    }

    @Test("Focused-app rehide and rehide turned off leave no section timer and stop the old monitor")
    func noSectionTimer() async {
        for change in [{ (world: RehideWorld) in world.settings.strategy = .focusedApp }, { $0.settings.autoRehide = false }] {
            let world = world(.timed, atOnce: false)
            world.pointerInArea = true
            world.controller.revealed(.hidden)
            change(world)
            world.controller.revealed(.hidden)
            await world.settle()
            #expect(world.moveHandlers.isEmpty)
            #expect(world.sleeps.isEmpty)
        }
    }

    /// A countdown already in progress must respect a disabled automatic-rehide preference.
    @Test("Disabling rehide stops a section countdown", arguments: [RehideStrategy.timed, .smart])
    func disablingStopsSectionCountdown(strategy: RehideStrategy) async {
        let world = world(strategy, atOnce: false)
        world.controller.revealed(.hidden)
        await world.settle()
        world.settings.autoRehide = false
        world.now += .seconds(2)
        world.sleepsReturnAtOnce = true

        await world.finishWaits()
        await world.settle()
        #expect(world.sectionHides.isEmpty)
        world.movePointer(over: .hidden, inArea: false)
        await world.settle()
        #expect(world.moveHandlers.isEmpty)
    }

    /// Eligibility and the final menu check both suspend, so each must honor a later disabled preference.
    @Test("Disabling rehide during a section menu check prevents hiding", arguments: [8, 9])
    func disablingDuringSectionMenuProbe(check: Int) async {
        let world = world(.timed)
        world.heldMenuCheck = check
        world.controller.revealed(.hidden)
        while world.menuChecks < check {
            await world.settle()
        }
        world.settings.autoRehide = false

        await world.finishWaits()
        await world.settle()

        #expect(world.sectionHides.isEmpty)
        world.movePointer(over: .hidden, inArea: false)
        #expect(world.moveHandlers.isEmpty)
    }

    /// An idle timed monitor must not start a new countdown after automatic rehiding is disabled.
    @Test("Disabling rehide releases an idle monitor on the next pointer move")
    func disablingStopsIdleMonitor() async {
        let world = world(.timed)
        world.pointerInArea = true
        world.controller.revealed(.hidden)
        world.settings.autoRehide = false

        world.movePointer(over: .hidden, inArea: false)
        await world.controller.waitUntilIdle()

        #expect(world.sectionHides.isEmpty)
        #expect(world.moveHandlers.isEmpty)
    }

    /// Hiding either section closes the presentation of both, so neither countdown may survive.
    @Test("Hiding a section stops every revealed section's countdown", arguments: [RehideStrategy.timed, .smart])
    func hidingStopsEverySection(strategy: RehideStrategy) async {
        let world = world(strategy, atOnce: false)
        world.controller.revealed(.hidden)
        world.controller.revealed(.alwaysHidden)
        world.controller.revealed(.alwaysHidden)
        await world.settle()
        #expect(world.sleeps.count == 2, "the repeated reveal replaces its old countdown")

        world.controller.hidden(.hidden)
        #expect(world.moveHandlers.isEmpty)
        world.now += .seconds(2)
        world.sleepsReturnAtOnce = true
        await world.finishWaits()
        await world.settle()

        #expect(world.sectionHides.isEmpty, "no countdown may hide a section after it closed")
        #expect(world.sleeps.count == 2)
    }

    /// A menu probe can return after closing cancelled the countdown; it must not restart anything.
    @Test("Closing during an eligibility menu probe cannot restart a section")
    func closingDuringEligibilityCannotRestart() async {
        let world = world(.timed)
        world.heldMenuCheck = 8
        world.controller.revealed(.hidden)
        while world.menuChecks < 8 {
            await world.settle()
        }
        let starts = world.monitorStarts.count
        world.controller.hidden(.hidden)
        world.pointerInArea = true

        await world.finishWaits()
        await world.settle()

        #expect(world.monitorStarts.count == starts)
        #expect(world.moveHandlers.isEmpty)
    }

    /// Hiding an already-hidden section closes nothing and must leave the other section's rehide alone.
    @Test("An already-hidden section preserves the open section's pointer monitor")
    func noOpHidePreservesOtherSection() {
        let world = world(.timed)
        world.pointerInArea = true
        world.controller.revealed(.hidden)
        world.controller.revealed(.alwaysHidden)

        world.controller.hidden(.alwaysHidden, closingPresentation: false)

        #expect(Set(world.moveHandlers.keys) == [.hidden])
        world.controller.hidden(.hidden)
        #expect(world.moveHandlers.isEmpty)
    }

    /// A timed reveal under the pointer still owns a monitor even before it has a countdown.
    @Test("Hiding a section stops the other section's idle pointer monitor")
    func hidingStopsIdlePointerMonitors() {
        let world = world(.timed)
        world.pointerInArea = true
        world.controller.revealed(.hidden)
        world.controller.revealed(.alwaysHidden)
        #expect(Set(world.moveHandlers.keys) == [.hidden, .alwaysHidden])

        world.controller.hidden(.hidden)

        #expect(world.moveHandlers.isEmpty)
        #expect(world.sleeps.isEmpty)
    }
}
