//
//  MacOS27StructuralControlOrderPolicyTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("macOS 27 structural control order policy")
struct MacOS27StructuralControlOrderPolicyTests {
    @Test("Hidden and Visible order does not require an Always Hidden divider")
    @MainActor
    func hiddenVisibleOrderDoesNotRequireAlwaysHiddenDivider() {
        let hidden = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.test.hidden", title: "Item-0"),
            windowID: 1
        )
        let hiddenDivider = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 2,
            sourcePID: nil
        )
        let visible = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.test.visible", title: "Item-0"),
            windowID: 3
        )

        let order = MenuBarItemManager.macOS27StructuralOrder(
            alwaysHiddenItems: [],
            alwaysHiddenControlItem: nil,
            hiddenItems: [hidden],
            hiddenControlItem: hiddenDivider,
            visibleSegment: [visible]
        )

        #expect(order.map(\.uniqueIdentifier) == [
            hidden.uniqueIdentifier,
            hiddenDivider.uniqueIdentifier,
            visible.uniqueIdentifier,
        ])
    }

    @Test("Ambient cache refresh preserves live menu bar positions")
    @MainActor
    func ambientCacheRefreshPreservesLivePositions() {
        #expect(
            !MenuBarItemManager.shouldEnforceMacOS27StructuralControlOrder(
                for: .ambientCacheRefresh
            )
        )
    }

    @Test("A revealed layout restore may repair structural positions")
    @MainActor
    func revealedLayoutRestoreMayRepairPositions() {
        #expect(
            MenuBarItemManager.shouldEnforceMacOS27StructuralControlOrder(
                for: .revealedLayoutRestore
            )
        )
    }

    @Test("Explicit layout repair may rewrite structural positions")
    @MainActor
    func explicitLayoutRepairMayRewritePositions() {
        #expect(
            MenuBarItemManager.shouldEnforceMacOS27StructuralControlOrder(
                for: .explicitLayoutRepair
            )
        )
    }
}
