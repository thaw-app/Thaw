//
//  CacheRebucketterTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

@MainActor
final class CacheRebucketterTests: XCTestCase {
    func testRebucketLiveItemGoesToAssignedSection() {
        let item = item(id: 1, title: "Hidden")
        let cache = cache(visible: [item])

        let rebucketed = rebucket(cache, assignments: [item.uniqueIdentifier: .hidden])

        XCTAssertEqual(rebucketed[.hidden], [item])
        XCTAssertTrue(rebucketed[.visible].isEmpty)
    }

    func testRebucketConcealedItemMissingFromAXRestoredFromSnapshot() {
        let item = item(id: 2, title: "Snapshot")
        let cache = cache()

        let rebucketed = rebucket(
            cache,
            assignments: [item.uniqueIdentifier: .hidden],
            snapshots: [item.uniqueIdentifier: item]
        )

        XCTAssertEqual(rebucketed[.hidden], [item])
    }

    func testRebucketAlwaysHiddenDisabledFlattensAlwaysHiddenIntoHidden() {
        let item = item(id: 3, title: "Always")
        let cache = cache(visible: [item])

        let rebucketed = rebucket(
            cache,
            assignments: [item.uniqueIdentifier: .alwaysHidden],
            allowsAlwaysHidden: false
        )

        XCTAssertEqual(rebucketed[.hidden], [item])
        XCTAssertTrue(rebucketed[.alwaysHidden].isEmpty)
    }

    func testRebucketAlwaysHiddenEnabledKeepsSeparate() {
        let item = item(id: 4, title: "Always")
        let cache = cache(visible: [item])

        let rebucketed = rebucket(
            cache,
            assignments: [item.uniqueIdentifier: .alwaysHidden],
            allowsAlwaysHidden: true
        )

        XCTAssertEqual(rebucketed[.alwaysHidden], [item])
        XCTAssertTrue(rebucketed[.hidden].isEmpty)
    }

    func testRebucketVisibleItemStaysVisible() {
        let item = item(id: 5, title: "Visible")
        let cache = cache(visible: [item])

        let rebucketed = rebucket(cache, assignments: [:])

        XCTAssertEqual(rebucketed[.visible], [item])
    }

    private func rebucket(
        _ input: MenuBarItemManager.ItemCache,
        assignments: [String: MenuBarSection.Name],
        snapshots: [String: MenuBarItem] = [:],
        allowsAlwaysHidden: Bool = true
    ) -> MenuBarItemManager.ItemCache {
        CacheRebucketter.rebucket(
            input,
            sectionFor: { assignments[$0.uniqueIdentifier] ?? .visible },
            sectionAssignment: assignments,
            allowsAlwaysHidden: allowsAlwaysHidden,
            retainedSnapshotFor: { snapshots[$0] },
            orderedItems: { items, _ in items }
        )
    }

    private func cache(
        visible: [MenuBarItem] = [],
        hidden: [MenuBarItem] = [],
        alwaysHidden: [MenuBarItem] = []
    ) -> MenuBarItemManager.ItemCache {
        var cache = MenuBarItemManager.ItemCache(displayID: nil)
        cache[.visible] = visible
        cache[.hidden] = hidden
        cache[.alwaysHidden] = alwaysHidden
        return cache
    }

    private func item(id: CGWindowID, title: String) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.\(title.lowercased())", title: title),
            windowID: id,
            bounds: CGRect(x: CGFloat(id) * 24, y: 0, width: 20, height: 22)
        )
    }
}
