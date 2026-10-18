//
//  SettlingKindTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Settling kinds")
struct SettlingKindTests {
    @Test("A no-op spacing apply leaves a display settling running")
    func noOpSpacingKeepsDisplaySettling() {
        let manager = MenuBarItemManager()
        defer { manager.startupSettlingTask?.cancel() }

        manager.startSettlingPeriod(reason: "displayConnect")
        manager.startSettlingPeriod(reason: "spacingRelaunch:screenParametersChanged:preflight")
        manager.cancelSettlingPeriod(reason: "spacingRelaunch:screenParametersChanged:noOp")

        #expect(manager.isInStartupSettling)
        #expect(manager.settlingKind == .event)
    }

    @Test("A no-op spacing apply still cancels its own preflight")
    func noOpSpacingCancelsOwnPreflight() {
        let manager = MenuBarItemManager()
        defer { manager.startupSettlingTask?.cancel() }

        manager.startSettlingPeriod(reason: "spacingRelaunch:configurationsChanged:preflight")
        manager.cancelSettlingPeriod(reason: "spacingRelaunch:configurationsChanged:noOp")

        #expect(!manager.isInStartupSettling)
    }

    @Test("Weaker settlings yield to stronger ones")
    func yieldOrder() {
        #expect(MenuBarItemManager.settlingYields(incoming: .preflight, to: .event))
        #expect(!MenuBarItemManager.settlingYields(incoming: .preflight, to: .preflight))
        #expect(MenuBarItemManager.settlingYields(incoming: .event, to: .cold))
        #expect(MenuBarItemManager.settlingYields(incoming: .event, to: .expectedSet))
        #expect(!MenuBarItemManager.settlingYields(incoming: .event, to: .preflight))
        #expect(!MenuBarItemManager.settlingYields(incoming: .cold, to: .event))
    }

    @Test("Only the launch settling reads sections from the bar")
    func onlyLaunchSettlingAdoptsMembership() {
        #expect(MenuBarItemManager.settleAdoptsObservedMembership(incoming: .cold, replacing: nil))
        #expect(MenuBarItemManager.settleAdoptsObservedMembership(incoming: .expectedSet, replacing: .cold))
        #expect(MenuBarItemManager.settleAdoptsObservedMembership(incoming: .cold, replacing: .event))
    }

    @Test("An app launch, display change or spacing wave keeps the sections set in Layout", arguments: [
        MenuBarItemManager.SettlingKind.event, .expectedSet, .preflight,
    ])
    func laterSettlingsKeepAuthoredSections(kind: MenuBarItemManager.SettlingKind) {
        #expect(!MenuBarItemManager.settleAdoptsObservedMembership(incoming: kind, replacing: nil))
        #expect(!MenuBarItemManager.settleAdoptsObservedMembership(incoming: kind, replacing: .event))
        #expect(!MenuBarItemManager.settleAdoptsObservedMembership(incoming: kind, replacing: .expectedSet))
    }
}
