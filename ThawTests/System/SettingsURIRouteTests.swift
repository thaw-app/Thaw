//
//  SettingsURIRouteTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Which thaw:// hosts wait for the Settings URI switch and an approved sender.
@Suite("Settings URI routes")
struct SettingsURIRouteTests {
    @Test("Settings, launcher and item-driving hosts need an approved sender", arguments: [
        "set", "toggle", "get", "authorize", "reveal-item", "list-items", "activate-item",
        "list-profiles", "apply-profile", "get-appearance", "move-item", "proxy-press", "PROXY-PRESS", "toggle-thawbar", "dump-items",
    ])
    func gatedHostsNeedApproval(host: String) {
        #expect(SettingsURIRoute.requiresAuthorization(host))
    }

    @Test("Every launcher operation is gated")
    func launcherOperationsAreGated() {
        for operation in LauncherURIOperation.allCases {
            #expect(SettingsURIRoute.requiresAuthorization(operation.rawValue), "\(operation.rawValue)")
        }
    }

    @Test("Actions a hotkey can also run stay open to any sender", arguments: [
        "toggle-hidden", "toggle-always-hidden", "toggle-swap", "search", "toggle-application-menus",
        "toggle-zen-mode", "toggle-layout-editor", "open-settings", "item-hints", "", "unknown",
    ])
    func hotkeyActionsStayOpen(host: String) {
        #expect(!SettingsURIRoute.requiresAuthorization(host))
    }
}
