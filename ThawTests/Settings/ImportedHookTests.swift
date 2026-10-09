//
//  ImportedHookTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
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
