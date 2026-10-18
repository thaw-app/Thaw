//
//  ImportedHookTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
import ThawModuleKit

@Suite("A profile from a file cannot run its scripts until the user switches them on")
struct ImportedHookTests {
    @Test("Both hooks come in switched off, with their paths and timeouts kept")
    func hooksArriveDisabled() {
        let shipped = ProfileAutomation(
            preHook: HookScript(path: "/tmp/pre.sh", timeoutSeconds: 12, isEnabled: true),
            postHook: HookScript(path: "/tmp/post.scpt", timeoutSeconds: 3, isEnabled: true)
        )

        let imported = shipped.disabledUntilApproved

        #expect(imported.preHook == HookScript(path: "/tmp/pre.sh", timeoutSeconds: 12, isEnabled: false))
        #expect(imported.postHook == HookScript(path: "/tmp/post.scpt", timeoutSeconds: 3, isEnabled: false))
    }

    @Test("A profile with no hooks, or one hook, keeps that shape")
    func missingHooksStayMissing() {
        #expect(ProfileAutomation().disabledUntilApproved.isEmpty)

        let onlyPost = ProfileAutomation(postHook: HookScript(path: "/tmp/post.sh")).disabledUntilApproved
        #expect(onlyPost.preHook == nil)
        #expect(onlyPost.postHook?.isEnabled == false)
    }
}

@Suite("Hook script rules")
struct HookScriptRulesTests {
    @Test("AppleScript files run through osascript, whatever the case of the extension")
    func appleScriptExtensions() {
        #expect(HookScript(path: "/tmp/a.scpt").usesOSAScript)
        #expect(HookScript(path: "/tmp/a.AppleScript").usesOSAScript)
        #expect(HookScript(path: "/tmp/a.scptd").usesOSAScript)
        #expect(!HookScript(path: "/tmp/a.sh").usesOSAScript)
        #expect(!HookScript(path: "/tmp/script").usesOSAScript)
    }

    @Test("A timeout outside 1 to 300 seconds runs clamped")
    func timeoutIsClamped() {
        #expect(HookScript(path: "/tmp/a.sh", timeoutSeconds: 0).clampedTimeout == 1)
        #expect(HookScript(path: "/tmp/a.sh", timeoutSeconds: 900).clampedTimeout == 300)
        #expect(HookScript(path: "/tmp/a.sh").clampedTimeout == HookScript.defaultTimeout)
    }
}
