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

/// The alphabetical section sort (#936): localized, case-insensitive order by
/// display name, so a crowded hidden section is scannable without dragging.
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

    /// `applyProfileLayout` relaxes concealed order by default so background work
    /// leaves off-screen items alone; Sort A→Z enforces it so a concealed sort reaches the bar.
    @Test("A concealed-section sort plans moves only when enforced")
    func concealedSortPlansMovesOnlyWhenEnforced() {
        // The bar holds the two hidden items reversed; visible stays put.
        let sectionMap = ["a": "visible", "b": "hidden", "c": "hidden"]
        let current = ["a", "c", "b"]
        let desired = ["a", "b", "c"]

        // Background reapply: relaxation keeps the bar's hidden order, so no moves.
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

        // Sort A->Z skips relaxation, so the LCS plans the swap.
        #expect(
            !LayoutSolver.planLCSMoveSequence(
                currentNoControls: current,
                desiredNoControls: desired,
                sectionMap: sectionMap
            ).isEmpty
        )
    }
}

/// Without an active profile, Sort A->Z goes through the saved-layout apply,
/// which relaxes concealed order, so the sort arms a one-shot flag that apply
/// consumes. Without it a concealed sort persists but never reaches the bar (#1116).
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
        // Sorted by displayName, so identifiers come back alphabetical.
        #expect(sorted?.count == 3)
        // Armed for the next saved-layout apply to consume.
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
