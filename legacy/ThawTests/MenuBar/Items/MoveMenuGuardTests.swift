//
//  MoveMenuGuardTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Covers `EventError.menuTrackingActive` classification and description, the
/// pure seam behind deferring moves while an item's menu is tracking (#739, #746).
///
/// The deciding paths (`isAnyMenuBarItemMenuOpen()`, the ~5s wait in `move(...)`,
/// and the early-outs in `applySavedLayout`/`applyProfileLayout`) need live
/// Accessibility state and were verified manually.
@Suite("Move-menu guard error classification")
struct MoveMenuGuardTests {
    private func makeItem() -> MenuBarItem {
        .fixture(
            tag: .appItem(bundleID: "com.example.wifi", title: "Wi-Fi"),
            windowID: 42
        )
    }

    @Test("menuTrackingActive is distinguishable via pattern match")
    func menuTrackingActiveIsPatternMatchable() {
        let item = makeItem()
        let error = MenuBarItemManager.EventError.menuTrackingActive(item)

        // Mirrors LayoutBarPaddingView's catch, which logs this case instead of alerting.
        if case .menuTrackingActive = error {
            // expected
        } else {
            Issue.record("Expected .menuTrackingActive to match itself")
        }

        if case .cannotComplete = error {
            Issue.record(".menuTrackingActive must not match .cannotComplete")
        }
    }

    @Test("menuTrackingActive has non-empty, item-specific description")
    func menuTrackingActiveDescription() {
        let item = makeItem()
        let error = MenuBarItemManager.EventError.menuTrackingActive(item)

        #expect(error.description.contains("menuTrackingActive"))
        #expect(error.description.contains("\(item.tag)"))
    }

    @Test("menuTrackingActive has a human-readable errorDescription")
    func menuTrackingActiveErrorDescription() throws {
        let item = makeItem()
        let error = MenuBarItemManager.EventError.menuTrackingActive(item)

        let description = try #require(error.errorDescription)
        #expect(!description.isEmpty)
        #expect(description.contains(item.displayName))
    }

    @Test("menuTrackingActive is distinct from other EventError cases")
    func menuTrackingActiveIsDistinctFromCannotComplete() {
        let item = makeItem()
        let tracking = MenuBarItemManager.EventError.menuTrackingActive(item)
        let cannotComplete = MenuBarItemManager.EventError.cannotComplete

        #expect(tracking.description != cannotComplete.description)
    }
}
