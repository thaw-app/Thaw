//
//  ExternalLayoutChangeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

/// Observing a layout change is not permission to undo it. These pin the
/// policy that decides who may move items, independent of the AX pipeline.
@Suite("External layout changes")
struct ExternalLayoutChangeTests {
    private typealias Request = MenuBarItemManager.OverflowRebalanceRequest

    @Test(
        "Only an explicit request may enforce order",
        arguments: zip(
            [LayoutChangeReason.externalChange, .userReorder, .profileApply, .revealRestore, .settingChange],
            [false, true, true, true, true]
        )
    )
    func enforcementFollowsTheReason(reason: LayoutChangeReason, permitted: Bool) {
        #expect(reason.permitsOrderEnforcement == permitted)
        #expect(reason.isUserInitiated == permitted)
    }

    @Test("A reveal restores what was recorded but is not an authored edit")
    func revealIsNotAnAuthoredEdit() {
        #expect(!LayoutChangeReason.revealRestore.isAuthoredEdit)
        #expect(!LayoutChangeReason.externalChange.isAuthoredEdit)
        #expect(LayoutChangeReason.userReorder.isAuthoredEdit)
        #expect(LayoutChangeReason.profileApply.isAuthoredEdit)
        #expect(LayoutChangeReason.settingChange.isAuthoredEdit)
    }

    @Test("An observed change coalesced around an explicit request does not demote it")
    func explicitOverflowRequestSurvivesCoalescing() {
        let explicit = Request(reason: .profileApply, immediate: false)
        let observed = Request(reason: .externalChange, immediate: false)

        #expect(observed.merged(into: explicit) == explicit)
        #expect(explicit.merged(into: observed) == explicit)
        #expect(observed.merged(into: nil) == observed)
    }

    @Test("A probe transition stays immediate but never earns order enforcement")
    func immediacyIsStickyWithoutPrivilege() {
        let probe = Request(reason: .externalChange, immediate: true)
        let later = Request(reason: .externalChange, immediate: false)

        let merged = later.merged(into: probe)
        #expect(merged.immediate)
        #expect(!merged.reason.permitsOrderEnforcement)
    }
}
