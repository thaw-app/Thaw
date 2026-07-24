//
//  MoveMenuGuardTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Tests for the pure error-classification seam introduced to support
/// deferring menu bar item moves while an item's menu (Wi-Fi picker, input
/// method panel, etc.) is tracking (#739, #746).
///
/// The moving parts that actually decide *whether* to defer a move —
/// `isAnyMenuBarItemMenuOpen()`, the bounded wait loop in `move(...)`, and
/// the early-out checks in `applySavedLayout`/`applyProfileLayout` — all
/// depend on live Accessibility state (real menu bar item menus tracking)
/// and can't be exercised without heavy scaffolding or a running menu bar.
/// Those paths were verified manually:
///  - `move(...)` waits up to ~5s for `isAnyMenuBarItemMenuOpen()` to clear
///    before throwing `.menuTrackingActive`, confirmed by reading the
///    guard placement in `MenuBarItemManager.swift` immediately after the
///    `appState` guard and before the blocked-item (`x == -1`) check.
///  - `applySavedLayout` / `applyProfileLayout` were confirmed to check
///    `isAnyMenuBarItemMenuOpen()` immediately after their respective
///    sourcePID guards, each logging a distinct, greppable reason string
///    ("applySavedLayout: skipping, a menu bar item menu is open" /
///    "applyProfileLayout: skipping, a menu bar item menu is open").
///  - The Wi-Fi-menu manual reproduction described in the plan requires a
///    live system Wi-Fi picker and is out of scope for CI.
///
/// What IS a pure, unit-testable seam is `EventError.menuTrackingActive`'s
/// classification and description formatting, exercised below.
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

        // Mirrors the catch-clause pattern used in LayoutBarPaddingView to
        // route this case to a log-only path instead of surfacing an alert.
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
