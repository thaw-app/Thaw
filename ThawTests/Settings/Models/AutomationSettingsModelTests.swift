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
@Suite("Automation settings and global hooks", .serialized, .scratchDefaults)
struct AutomationSettingsModelTests {
    @Test("Each phase keeps its own global hook, and saving nil clears only that phase")
    func globalHooksPerPhase() {
        let pre = HookScript(path: "/tmp/pre.sh", timeoutSeconds: 12, isEnabled: false)
        let post = HookScript(path: "/tmp/post.applescript")

        HookScript.saveGlobal(pre, phase: .pre)
        HookScript.saveGlobal(post, phase: .post)
        #expect(HookScript.loadGlobal(.pre) == pre)
        #expect(HookScript.loadGlobal(.post) == post)

        HookScript.saveGlobal(nil, phase: .pre)
        #expect(HookScript.loadGlobal(.pre) == nil)
        #expect(HookScript.loadGlobal(.post) == post)
    }

    @Test("A stored global hook that does not decode reads as none")
    func undecodableGlobalHook() {
        Defaults.set(Data("not json".utf8), forKey: .globalPostProfileHook)
        #expect(HookScript.loadGlobal(.post) == nil)
    }

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
