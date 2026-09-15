//
//  HideApplicationMenusPolicyTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// Covers the activation-policy decision in front of
/// ``MenuBarManager/hideApplicationMenus(manual:)``.
///
/// The 25 ms retry talks to `NSApp`, so what is pinned here is the choice of
/// policy: a clean Dock stays accessory unless explicit UI has already asked
/// for `.regular`.
@Suite("Hide application menus activation policy")
struct HideApplicationMenusPolicyTests {
    @Test("Toggling the menu bar uses regular activation by default")
    func defaultPathUsesRegularActivation() {
        let policy = MenuBarManager.activationPolicyForHidingApplicationMenus(
            hideDockIconWhenToggling: false,
            explicitUIWantsRegularActivation: false
        )

        #expect(policy == .regular)
    }

    @Test("The hide-Dock-icon setting keeps accessory activation")
    func hideDockIconSettingUsesAccessoryActivation() {
        let policy = MenuBarManager.activationPolicyForHidingApplicationMenus(
            hideDockIconWhenToggling: true,
            explicitUIWantsRegularActivation: false
        )

        #expect(policy == .accessory)
    }

    @Test("Explicit UI keeps regular activation even when the Dock icon is hidden")
    func explicitUIWinsOverHideDockIconSetting() {
        let policy = MenuBarManager.activationPolicyForHidingApplicationMenus(
            hideDockIconWhenToggling: true,
            explicitUIWantsRegularActivation: true
        )

        #expect(policy == .regular)
    }

    @Test("Explicit UI still uses regular activation when the setting is off")
    func explicitUIUsesRegularActivationWhenSettingIsOff() {
        let policy = MenuBarManager.activationPolicyForHidingApplicationMenus(
            hideDockIconWhenToggling: false,
            explicitUIWantsRegularActivation: true
        )

        #expect(policy == .regular)
    }

    @Test("A manual hide-application-menus toggle still uses regular activation")
    func manualToggleUsesRegularActivationEvenWhenHidingDockIcon() {
        let policy = MenuBarManager.activationPolicyForHidingApplicationMenus(
            hideDockIconWhenToggling: true,
            explicitUIWantsRegularActivation: false,
            isManualToggle: true
        )

        #expect(policy == .regular)
    }

    @Test("Turning the setting on restores an automatic hide")
    func turningSettingOnRestoresAutomaticHide() {
        let action = MenuBarManager.automaticHideReconcileAction(
            hideDockIconWhenToggling: true,
            isHidingApplicationMenus: true,
            isManuallyHidingApplicationMenus: false,
            explicitUIWantsRegularActivation: false
        )

        #expect(action == .restoreApplicationMenus)
    }

    @Test("Turning the setting on while explicit UI is up only clears automatic hide state")
    func turningSettingOnDuringExplicitUIClearsAutomaticHideState() {
        let action = MenuBarManager.automaticHideReconcileAction(
            hideDockIconWhenToggling: true,
            isHidingApplicationMenus: true,
            isManuallyHidingApplicationMenus: false,
            explicitUIWantsRegularActivation: true
        )

        #expect(action == .clearAutomaticHideState)
    }

    @Test("Turning the setting on leaves a manual hide alone")
    func turningSettingOnPreservesManualHide() {
        let action = MenuBarManager.automaticHideReconcileAction(
            hideDockIconWhenToggling: true,
            isHidingApplicationMenus: true,
            isManuallyHidingApplicationMenus: true,
            explicitUIWantsRegularActivation: false
        )

        #expect(action == .none)
    }

    @Test("Turning the setting off leaves hide state alone")
    func turningSettingOffDoesNotReconcileHideState() {
        let action = MenuBarManager.automaticHideReconcileAction(
            hideDockIconWhenToggling: false,
            isHidingApplicationMenus: true,
            isManuallyHidingApplicationMenus: false,
            explicitUIWantsRegularActivation: false
        )

        #expect(action == .none)
    }
}
