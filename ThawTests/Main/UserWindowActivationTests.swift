//
//  UserWindowActivationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// Covers the activation policy for windows the user opens (Settings,
/// Permissions, onboarding, search, the Thaw Bar).
///
/// Any switch to `.regular`, even the 50 ms launch warm-up, makes macOS add
/// Thaw to the Dock's recent apps. With "Show Dock icon while Settings is
/// open" turned off, Thaw has to stay `.accessory` and only activate.
@Suite("User window activation")
struct UserWindowActivationTests {
    @Test("With the Dock icon on, user windows activate as a regular app")
    func dockIconOnUsesRegular() {
        #expect(AppState.activationPolicyForUserWindow(showDockIconWithSettings: true) == .regular)
    }

    @Test("With the Dock icon off, user windows keep the current policy")
    func dockIconOffKeepsPolicy() {
        #expect(AppState.activationPolicyForUserWindow(showDockIconWithSettings: false) == nil)
    }

    /// Toggling the setting while Settings is open switches the policy right
    /// away instead of waiting for the next window.
    @Test("Changing the setting with a window open picks the matching policy")
    func openWindowPolicyFollowsTheSetting() {
        #expect(AppState.activationPolicyForOpenUserWindows(showDockIconWithSettings: true) == .regular)
        #expect(AppState.activationPolicyForOpenUserWindows(showDockIconWithSettings: false) == .accessory)
    }

    /// Read before General settings load: on the missing-permissions path the
    /// model still holds its default, so a stored opt-out has to come from here.
    @Test("The stored preference wins, and an unwritten one reads as the default")
    func storedPreferenceIsRead() {
        #expect(!AppState.showDockIconWithSettings(storedValue: false))
        #expect(AppState.showDockIconWithSettings(storedValue: true))
        #expect(AppState.showDockIconWithSettings(storedValue: nil) == Defaults.DefaultValue.showDockIconWithSettings)
        #expect(AppState.showDockIconWithSettings(storedValue: "not a bool") == Defaults.DefaultValue.showDockIconWithSettings)
    }

    @Test("The launch warm-up runs only when Thaw may become regular")
    func warmUpFollowsTheSetting() {
        #expect(AppState.warmsUpActivationPolicy(showDockIconWithSettings: true))
        #expect(!AppState.warmsUpActivationPolicy(showDockIconWithSettings: false))
    }

    /// The raw value is the UserDefaults key on disk and in Settings URIs.
    @Test("The setting's stored key name is stable")
    func storedKeyNameIsStable() {
        #expect(Defaults.Key.showDockIconWithSettings.rawValue == "ShowDockIconWithSettings")
    }

    @Test("The shipped default keeps today's behaviour")
    func defaultKeepsTheDockIcon() {
        #expect(Defaults.DefaultValue.showDockIconWithSettings)
    }
}
