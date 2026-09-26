//
//  AutomationHookSettingsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// The global hooks load once at init; the `didSet` observers must not echo
/// them back to `UserDefaults` on every launch.
@MainActor
@Suite("Automation hook settings", .serialized)
struct AutomationHookSettingsTests {
    @Test("Both global hooks are loaded at init")
    func globalHooksAreLoadedAtInit() throws {
        try withScratchDefaults { _ in
            let pre = HookScript(path: "/tmp/thaw-pre.sh", timeoutSeconds: 7, isEnabled: true)
            let post = HookScript(path: "/tmp/thaw-post.sh", timeoutSeconds: 12, isEnabled: false)
            HookScript.saveGlobal(pre, phase: .pre)
            HookScript.saveGlobal(post, phase: .post)

            let settings = AutomationHookSettings()

            #expect(settings.globalPreHook == pre)
            #expect(settings.globalPostHook == post)
        }
    }

    @Test("Unconfigured global hooks load as nil rather than as empty scripts")
    func unconfiguredGlobalHooksLoadAsNil() throws {
        try withScratchDefaults { _ in
            let settings = AutomationHookSettings()

            #expect(settings.globalPreHook == nil)
            #expect(settings.globalPostHook == nil)
        }
    }

    /// The stored bytes are deliberately in an order and spacing that
    /// `JSONEncoder` would never emit, so an echo from the `didSet`
    /// observers would rewrite them and this comparison would fail.
    @Test("Loading at init does not write the hooks back to defaults")
    func loadingAtInitDoesNotEchoBackToDefaults() throws {
        try withScratchDefaults { _ in
            let planted = Data(#"{ "isEnabled" : true, "timeoutSeconds" : 7, "path" : "/tmp/thaw-pre.sh" }"#.utf8)
            Defaults.set(planted, forKey: .globalPreProfileHook)

            let settings = AutomationHookSettings()

            #expect(settings.globalPreHook?.path == "/tmp/thaw-pre.sh")
            #expect(Defaults.data(forKey: .globalPreProfileHook) == planted)
        }
    }

    /// The contrast that makes the previous test meaningful: once `init` has
    /// returned, an assignment *is* persisted.
    @Test("An assignment after init is persisted")
    func assigningAfterInitPersists() throws {
        try withScratchDefaults { _ in
            let settings = AutomationHookSettings()
            let hook = HookScript(path: "/tmp/thaw-later.sh", timeoutSeconds: 3, isEnabled: true)

            settings.globalPostHook = hook

            #expect(HookScript.loadGlobal(.post) == hook)
            #expect(HookScript.loadGlobal(.pre) == nil)
        }
    }

    @Test("Clearing a hook after init removes it from defaults")
    func clearingAfterInitRemovesTheStoredHook() throws {
        try withScratchDefaults { _ in
            HookScript.saveGlobal(HookScript(path: "/tmp/thaw-pre.sh"), phase: .pre)
            let settings = AutomationHookSettings()
            #expect(settings.globalPreHook != nil)

            settings.globalPreHook = nil

            #expect(Defaults.data(forKey: .globalPreProfileHook) == nil)
            #expect(HookScript.loadGlobal(.pre) == nil)
        }
    }
}
