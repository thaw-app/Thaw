//
//  ApplicationMenuHiderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel
import Testing
@testable import Thaw

/// What a section reveal or conceal does to the application menus, and the hider before setup.
@MainActor
@Suite("Application menu hider", .serialized, .scratchDefaults)
struct ApplicationMenuHiderTests {
    @Test("With both hidden sections closed, only automatic hiding is undone")
    func closedSectionsRestoreOnlyAutomaticHiding() {
        let automatic = ApplicationMenuHider.reconciliation(
            isShowingHidden: false, isShowingAlwaysHidden: false, isHiding: true, isManual: false
        )
        #expect(automatic == .showMenus)
        let manual = ApplicationMenuHider.reconciliation(
            isShowingHidden: false, isShowingAlwaysHidden: false, isHiding: true, isManual: true
        )
        #expect(manual == .leaveMenus)
        let notHiding = ApplicationMenuHider.reconciliation(
            isShowingHidden: false, isShowingAlwaysHidden: false, isHiding: false, isManual: false
        )
        #expect(notHiding == .leaveMenus)
    }

    @Test("A shown section is checked for room, the always-hidden one first")
    func shownSectionIsChecked() {
        let hidden = ApplicationMenuHider.reconciliation(
            isShowingHidden: true, isShowingAlwaysHidden: false, isHiding: false, isManual: false
        )
        #expect(hidden == .hideIfSectionNeedsRoom(.hidden))
        let both = ApplicationMenuHider.reconciliation(
            isShowingHidden: true, isShowingAlwaysHidden: true, isHiding: true, isManual: true
        )
        #expect(both == .hideIfSectionNeedsRoom(.alwaysHidden))
        let alwaysHidden = ApplicationMenuHider.reconciliation(
            isShowingHidden: false, isShowingAlwaysHidden: true, isHiding: false, isManual: false
        )
        #expect(alwaysHidden == .hideIfSectionNeedsRoom(.alwaysHidden))
    }

    @Test("Without setup, hiding, showing and toggling change nothing")
    func withoutSetup() {
        let hider = ApplicationMenuHider()
        hider.hideApplicationMenus(manual: true)
        #expect(!hider.isHidingApplicationMenus)
        hider.toggleApplicationMenus()
        #expect(!hider.isHidingApplicationMenus)
        hider.showApplicationMenus()
        #expect(!hider.isHidingApplicationMenus)
    }

    @Test("With both sections closed and nothing hidden, reconciling leaves the menus alone", arguments: [false, true])
    func closedSectionsLeaveMenus(hidingEnabled: Bool) {
        let appState = AppState()
        appState.settings.general.hideApplicationMenus = hidingEnabled
        let hider = ApplicationMenuHider()
        hider.performSetup(with: appState)
        hider.reconcileApplicationMenuVisibility()
        #expect(!hider.isHidingApplicationMenus)
    }

    @Test("One subscription covers every section's control state")
    func oneSubscriptionForAllSections() {
        let hider = ApplicationMenuHider()
        var bag = Set<AnyCancellable>()
        hider.observeSectionStates(of: [MenuBarSection(name: .hidden), MenuBarSection(name: .alwaysHidden)], into: &bag)
        #expect(bag.count == 1)
    }

    // MARK: - Against a fake environment

    /// The live calls a hider made, in order.
    @MainActor
    private final class Calls {
        var log: [String] = []
    }

    private func environment(
        calls: Calls,
        sleeps: RecordedSleeps,
        screen: NSScreen? = nil,
        mode: MenuBarSection.PresentationMode = .inline
    ) -> ApplicationMenuHider.Environment {
        ApplicationMenuHider.Environment(
            activateAsRegular: { calls.log.append("activateAsRegular") },
            activate: { calls.log.append("activate") },
            deactivateToAccessory: { calls.log.append("deactivateToAccessory") },
            activeMenuBarScreen: { screen },
            mainScreen: { screen },
            presentationMode: { _, _ in mode },
            sleep: { try sleeps.sleep(for: $0) }
        )
    }

    @Test("Hiding activates as a regular app, waits 25 ms, then activates again, once")
    func hideActivatesTwice() async throws {
        let appState = AppState()
        let calls = Calls()
        let sleeps = RecordedSleeps()
        let hider = ApplicationMenuHider()
        hider.performSetup(with: appState, environment: environment(calls: calls, sleeps: sleeps))
        let task = try #require(hider.hideApplicationMenus())
        #expect(hider.isHidingApplicationMenus)
        await task.value
        #expect(calls.log == ["activateAsRegular", "activate"])
        #expect(sleeps.durations == [.milliseconds(25)])
        #expect(hider.hideApplicationMenus(manual: true) == nil)
        #expect(calls.log.count == 2)
    }

    @Test("Showing before the activation task runs skips both activations")
    func showBeforeActivation() async throws {
        let appState = AppState()
        let calls = Calls()
        let hider = ApplicationMenuHider()
        hider.performSetup(with: appState, environment: environment(calls: calls, sleeps: RecordedSleeps()))
        let task = try #require(hider.hideApplicationMenus())
        hider.showApplicationMenus()
        await task.value
        #expect(calls.log == ["deactivateToAccessory"])
        #expect(!hider.isHidingApplicationMenus)
    }

    @Test("Toggling hides by hand, and closed sections then leave the menus hidden until toggled back")
    func toggleTakesManualOwnership() async throws {
        let appState = AppState()
        appState.settings.general.hideApplicationMenus = true
        let calls = Calls()
        let hider = ApplicationMenuHider()
        hider.performSetup(with: appState, environment: environment(calls: calls, sleeps: RecordedSleeps()))
        hider.toggleApplicationMenus()
        #expect(hider.isHidingApplicationMenus)
        hider.reconcileApplicationMenuVisibility()
        #expect(hider.isHidingApplicationMenus)
        hider.toggleApplicationMenus()
        #expect(!hider.isHidingApplicationMenus)
        #expect(calls.log.last == "deactivateToAccessory")
    }

    @Test("Closed sections restore automatic hiding")
    func closedSectionsRestoreAutomaticHiding() async throws {
        let appState = AppState()
        appState.settings.general.hideApplicationMenus = true
        let calls = Calls()
        let hider = ApplicationMenuHider()
        hider.performSetup(with: appState, environment: environment(calls: calls, sleeps: RecordedSleeps()))
        await hider.hideApplicationMenus()?.value
        hider.reconcileApplicationMenuVisibility()
        #expect(!hider.isHidingApplicationMenus)
        #expect(calls.log == ["activateAsRegular", "activate", "deactivateToAccessory"])
    }

    @Test("A settled section that needs room hides the menus after 50 ms", arguments: [
        MenuBarSection.PresentationMode.inlineHidingApplicationMenus, .thawBar,
    ])
    func settledSectionNeedingRoomHides(mode: MenuBarSection.PresentationMode) async throws {
        let appState = AppState()
        let screen = try #require(NSScreen.screens.first)
        let sleeps = RecordedSleeps()
        let hider = ApplicationMenuHider()
        hider.performSetup(with: appState, environment: environment(calls: Calls(), sleeps: sleeps, screen: screen, mode: mode))
        let section = appState.menuBarManager.section(withName: .hidden)
        await hider.hideIfNeedingRoom(section, on: screen)?.value
        #expect(sleeps.durations.first == .milliseconds(50))
        #expect(hider.isHidingApplicationMenus)
    }

    @Test("An inline section, a missing section or a moved menu bar leaves the menus")
    func settledSectionLeavesMenus() async throws {
        let appState = AppState()
        let screen = try #require(NSScreen.screens.first)
        let hider = ApplicationMenuHider()
        let section = appState.menuBarManager.section(withName: .hidden)

        hider.performSetup(with: appState, environment: environment(calls: Calls(), sleeps: RecordedSleeps(), screen: screen))
        await hider.hideIfNeedingRoom(section, on: screen)?.value
        #expect(!hider.isHidingApplicationMenus)

        hider.performSetup(with: appState, environment: environment(calls: Calls(), sleeps: RecordedSleeps(), screen: screen, mode: .thawBar))
        await hider.hideIfNeedingRoom(nil, on: screen)?.value
        #expect(!hider.isHidingApplicationMenus)

        hider.performSetup(with: appState, environment: environment(calls: Calls(), sleeps: RecordedSleeps(), mode: .thawBar))
        await hider.hideIfNeedingRoom(section, on: screen)?.value
        #expect(!hider.isHidingApplicationMenus)
    }

    @Test("Without setup the delayed check does not start")
    func delayedCheckWithoutSetup() throws {
        let screen = try #require(NSScreen.screens.first)
        #expect(ApplicationMenuHider().hideIfNeedingRoom(nil, on: screen) == nil)
    }
}
