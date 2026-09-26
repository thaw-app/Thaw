//
//  SortSectionOrderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Covers the alphabetical section sort added for #936: a section's items
/// reorder by display name, localized and case-insensitive, so a crowded
/// hidden section can be made scannable without dragging each icon.
@Suite("Sort section order")
struct SortSectionOrderTests {
    private func item(_ bundleID: String, _ title: String, _ windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: .appItem(bundleID: bundleID, title: title),
            windowID: windowID,
            bounds: CGRect(x: 200, y: 0, width: 24, height: 22)
        )
    }

    @Test("Items are sorted by the key, case-insensitive and localized")
    func sortsByKeyCaseInsensitive() {
        let items = [
            item("com.z", "Zoom", 1),
            item("com.a", "alt-tab", 2),
            item("com.b", "Bartender", 3),
            item("com.apple", "AppleScript", 4),
        ]

        let sorted = LayoutSolver.sortedSectionIdentifiers(items) { $0.tag.title }

        #expect(sorted == [
            "com.a:alt-tab",
            "com.apple:AppleScript",
            "com.b:Bartender",
            "com.z:Zoom",
        ])
    }

    @Test("Items with the same key keep their relative order (stable)")
    func sortIsStableForEqualKeys() {
        let items = [
            item("com.first", "App", 1),
            item("com.second", "App", 2),
            item("com.third", "App", 3),
        ]

        let sorted = LayoutSolver.sortedSectionIdentifiers(items) { $0.tag.title }

        #expect(sorted == ["com.first:App", "com.second:App", "com.third:App"])
    }

    @Test("An empty section sorts to empty")
    func emptySectionSortsToEmpty() {
        #expect(LayoutSolver.sortedSectionIdentifiers([]) { $0.tag.title } == [])
    }

    /// `applyProfileLayout` relaxes concealed-section order by default so
    /// background work does not reorder off-screen items. Sort A→Z passes
    /// `enforceConcealedSectionOrder: true` to skip that relaxation, so a
    /// hidden/always-hidden sort reaches the bar instead of only persisting.
    @Test("A concealed-section sort plans moves only when enforced")
    func concealedSortPlansMovesOnlyWhenEnforced() {
        // Two hidden items the user wants in A→Z order; the bar holds them
        // reversed. Visible stays put either way.
        let sectionMap = ["a": "visible", "b": "hidden", "c": "hidden"]
        let current = ["a", "c", "b"]
        let desired = ["a", "b", "c"]

        // Default path (background reapply): relaxation surrenders the
        // hidden order, the LCS sees the bar as already correct, no moves.
        let relaxed = LayoutSolver.relaxConcealedSectionOrder(
            desiredNoControls: desired,
            currentNoControls: current,
            sectionMap: sectionMap
        )
        #expect(relaxed == current)
        #expect(
            LayoutSolver.planLCSMoveSequence(
                currentNoControls: current,
                desiredNoControls: relaxed,
                sectionMap: sectionMap
            ).isEmpty
        )

        // Enforced path (Sort A->Z): the relaxation is skipped, so the LCS
        // sees the sorted order and plans the swap.
        #expect(
            !LayoutSolver.planLCSMoveSequence(
                currentNoControls: current,
                desiredNoControls: desired,
                sectionMap: sectionMap
            ).isEmpty
        )
    }
}

/// Sort A->Z runs through two apply paths. With an active profile it calls
/// `reapplyActiveProfile(enforceConcealedSectionOrder: true)`. With no active
/// profile it reorders through the saved-layout apply, which relaxes
/// concealed-section order by default, so the sort arms a one-shot flag the
/// saved apply consumes. Without the flag a hidden/always-hidden sort
/// persists to disk but never reaches the bar (#1116).
@MainActor
@Suite("Sort section, no active profile")
final class SortSectionNoProfileTests {
    private func item(_ bundleID: String, _ title: String, _ windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: .appItem(bundleID: bundleID, title: title),
            windowID: windowID,
            bounds: CGRect(x: 200, y: 0, width: 24, height: 22)
        )
    }

    @Test("A concealed-section sort with no profile arms the saved-apply enforcement flag")
    func concealedSortWithNoProfileArmsFlag() {
        let manager = MenuBarItemManager()
        manager.itemCache[.hidden] = [
            item("com.z", "Zoom", 1),
            item("com.a", "alt-tab", 2),
            item("com.b", "Bartender", 3),
        ]

        let sorted = manager.sortSection(.hidden)

        #expect(sorted != nil, "sortSection should sort the populated hidden section")
        // The saved-order apply keys items by section key string; the sort
        // sorts the live items by displayName so the returned identifiers
        // come back in alphabetical order.
        #expect(sorted?.count == 3)
        // The one-shot flag is armed for the cache cycle's saved-layout
        // apply to consume.
        #expect(
            manager.enforceConcealedSectionOrderOnNextSavedApply,
            "no-profile sort must arm enforcement for the saved-layout apply"
        )
    }

    @Test("The saved-apply enforcement flag is off by default")
    func flagIsOffByDefault() {
        #expect(!MenuBarItemManager().enforceConcealedSectionOrderOnNextSavedApply)
    }
}
