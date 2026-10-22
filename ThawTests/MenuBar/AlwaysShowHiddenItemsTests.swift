//
//  AlwaysShowHiddenItemsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Observation
import Testing
@testable import Thaw

@MainActor
@Suite("Always show hidden items")
struct AlwaysShowHiddenItemsTests {
    @Test("Repeated section hides preserve Zen's hover lock and otherwise rearm hover", arguments: [false, true])
    func sectionHideCleansUpWithoutExitingZen(zen: Bool) {
        let manager = MenuBarManager()
        let section = MenuBarSection(name: .hidden)
        if zen {
            #expect(manager.toggleZenMode())
        }
        manager.showOnHoverAllowed = false
        manager.sections.forEach { $0.desiredState = .showSection }

        for _ in 0 ..< 3 {
            #expect(section.isHidden)
            section.hide(using: manager)
            #expect(manager.isZenModeActive == zen)
            #expect(manager.showOnHoverAllowed == !zen)
            #expect(manager.sections.allSatisfy { $0.desiredState == .hideSection })
        }
    }

    @Test("Inactive controller preserves manual reveals even when closing", arguments: [false, true])
    func inactiveControllerPreservesManualReveal(closingSections: Bool) {
        let state = ControllerState()
        state.enabledDisplayIDs = [2]
        state.section = .alwaysHidden
        let controller = state.makeController()
        for _ in 0 ..< 2 {
            controller.synchronize(closingSections: closingSections)
        }
        #expect(!controller.isEnabled)
        #expect(controller.shouldRestorePreZenReveals)
        #expect(state.section == .alwaysHidden)
        #expect(state.reveals.isEmpty)
        #expect(state.resets == 0)
    }

    @Test("Missing displays, Thaw Bar and Zen exclude always-show")
    func excludedPresentationsRemainUntouched() {
        let exclusions: [(CGDirectDisplayID?, Bool, Bool)] = [(nil, false, false), (1, true, false), (1, false, true)]
        for (displayID, thawBar, zen) in exclusions {
            let state = ControllerState()
            state.enabledDisplayIDs = [1]
            state.displayID = displayID
            state.usesThawBar = thawBar
            state.isZenModeActive = zen
            state.section = .hidden
            let controller = state.makeController()
            #expect(!controller.isEnabled)
            controller.synchronize(closingSections: true)
            #expect(controller.shouldRestorePreZenReveals)
            #expect(state.section == .hidden)
            #expect(state.reveals.isEmpty)
            #expect(state.resets == 0)
        }
    }

    @Test("Active policy preserves explicit reveals until closing", arguments: [nil, .hidden, .alwaysHidden] as [MenuBarSectionName?])
    func activePolicyKeepsHiddenRevealed(initialSection: MenuBarSectionName?) {
        let state = ControllerState()
        state.enabledDisplayIDs = [1]
        state.section = initialSection
        let controller = state.makeController()
        #expect(controller.isEnabled)
        for _ in 0 ..< 2 {
            controller.synchronize()
        }
        #expect(state.section == (initialSection ?? .hidden))
        #expect(state.reveals == (initialSection == nil ? [.hidden] : []))
        for _ in 0 ..< 2 {
            controller.synchronize(closingSections: true)
        }
        #expect(state.section == .hidden)
        #expect(state.reveals == (initialSection == .hidden ? [] : [.hidden]))
        #expect(state.resets == 0)
        #expect(!controller.shouldRestorePreZenReveals, "the policy owns this reveal; Zen exit hands it back")
    }

    @Test("Changing displays withdraws only the policy-owned reveal once")
    func changingActiveDisplayWithdrawsOwnedReveal() {
        let state = ControllerState()
        state.enabledDisplayIDs = [1]
        let controller = state.makeController()
        controller.synchronize()
        state.displayID = 2
        #expect(!controller.isEnabled)
        #expect(!controller.shouldRestorePreZenReveals)
        controller.synchronize()
        #expect(state.section == nil)
        state.section = .alwaysHidden
        controller.synchronize(closingSections: true)
        #expect(state.section == .alwaysHidden)
        #expect(state.reveals == [.hidden, nil])
        #expect(state.resets == 1)
        #expect(controller.shouldRestorePreZenReveals)
    }

    @Test("Zen exit hands an always-show reveal back to the policy, which restores it only when enabled", arguments: [false, true])
    func zenExitRespectsCurrentPolicy(enabledOnExit: Bool) {
        let state = ControllerState()
        state.enabledDisplayIDs = [1]
        let controller = state.makeController()
        controller.synchronize()
        state.isZenModeActive = true
        state.section = nil
        state.enabledDisplayIDs = enabledOnExit ? [1] : []
        controller.synchronize(closingSections: true)
        #expect(!controller.isEnabled)
        #expect(!controller.shouldRestorePreZenReveals)
        #expect(state.section == nil)
        #expect(state.reveals == [.hidden])
        #expect(state.resets == 0)
        state.isZenModeActive = false
        #expect(!controller.shouldRestorePreZenReveals, "the policy's reveal isn't replayed as the user's")
        for _ in 0 ..< 2 {
            controller.synchronize()
        }
        #expect(state.section == (enabledOnExit ? .hidden : nil))
        #expect(state.reveals == (enabledOnExit ? [.hidden, .hidden] : [.hidden]))
        #expect(state.resets == (enabledOnExit ? 0 : 1))
        #expect(controller.shouldRestorePreZenReveals == !enabledOnExit)
    }

    @Test("Configuration observations synchronize before refreshing controls", .timeLimit(.minutes(1)))
    func configurationChangesSynchronizePresentation() async {
        let state = ControllerState()
        state.enabledDisplayIDs = [1]
        let controller = state.makeController()
        let (updates, continuation) = AsyncStream<Bool>.makeStream()
        defer { continuation.finish() }
        controller.observeDisplaySettings {
            state.configurations
        } refreshControls: {
            continuation.yield(state.section == .hidden)
        }
        var iterator = updates.makeAsyncIterator()
        #expect(await iterator.next() == true)
        state.enabledDisplayIDs = []
        state.configurations["display"] = .defaultConfiguration
        #expect(await iterator.next() == false)
        #expect(state.section == nil)
        #expect(state.reveals == [.hidden, nil])
        #expect(state.resets == 1)
    }

    @MainActor
    @Observable
    final class ControllerState {
        var displayID: CGDirectDisplayID? = 1
        var configurations = [String: DisplayThawBarConfiguration]()
        var enabledDisplayIDs: Set<CGDirectDisplayID> = []
        var usesThawBar = false
        var isZenModeActive = false
        var section: MenuBarSectionName?
        var reveals = [MenuBarSectionName?]()
        var resets = 0

        func makeController() -> AlwaysShowHiddenItemsController {
            AlwaysShowHiddenItemsController(
                activeDisplayID: { self.displayID },
                alwaysShow: { self.enabledDisplayIDs.contains($0) },
                usesThawBar: { _ in self.usesThawBar },
                isZenModeActive: { self.isZenModeActive },
                revealedSection: { self.section },
                reveal: {
                    self.section = $0
                    self.reveals.append($0)
                },
                resetPresentation: { self.resets += 1 }
            )
        }
    }
}
