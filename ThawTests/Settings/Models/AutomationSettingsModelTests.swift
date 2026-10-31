//
//  AutomationSettingsModelTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Automation settings", .serialized, .scratchDefaults)
struct AutomationSettingsModelTests {
    @Test("An allowed app is named by its app name, or by its bundle ID when it has none")
    func whitelistedAppNames() {
        let named = AutomationSettings.WhitelistedApp(bundleId: "com.example.a", appName: "Alpha", icon: nil)
        let unnamed = AutomationSettings.WhitelistedApp(bundleId: "com.example.b", appName: nil, icon: nil)
        #expect(named.id == "com.example.a")
        #expect(named.displayName == "Alpha")
        #expect(unnamed.displayName == "com.example.b")
    }

    @Test("Removing an allowed app takes it off the list the pane shows")
    func removeFromWhitelist() {
        let kept = "com.example.thawtests.kept.\(UUID().uuidString)"
        let removed = "com.example.thawtests.removed.\(UUID().uuidString)"
        SettingsURIHandler.addToWhitelist(bundleId: kept, codeHash: "c0ffee")
        SettingsURIHandler.addToWhitelist(bundleId: removed, codeHash: "beef")
        let settings = AutomationSettings()
        #expect(Set(settings.whitelistedApps.map(\.bundleId)) == [kept, removed])

        settings.removeFromWhitelist(bundleId: removed)

        #expect(settings.whitelistedApps.map(\.bundleId) == [kept])
        #expect(SettingsURIHandler.getWhitelist() == [kept])
    }
}
