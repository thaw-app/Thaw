//
//  MenuBarItemAXProviderTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

@available(macOS 27, *)
final class MenuBarItemAXProviderTests: XCTestCase {
    func testAssembleAssignsIncrementalInstanceIndexPerNamespace() {
        let raw = [
            rawItem(bundleID: "com.example.app", title: "Metric", x: 0),
            rawItem(bundleID: "com.example.app", title: "Metric", x: 50),
        ]

        let items = MenuBarItemAXProvider.assemble(raw)

        XCTAssertEqual(items.count, 2)
        XCTAssertNotEqual(items[0].uniqueIdentifier, items[1].uniqueIdentifier)
        XCTAssertTrue(items[1].uniqueIdentifier.hasSuffix(":1"))
    }

    func testAssembleDuplicateNamespaceTitleHandled() {
        let raw = [
            rawItem(bundleID: "com.example.app", title: "Same", x: 0),
            rawItem(bundleID: "com.example.app", title: "Same", x: 10),
            rawItem(bundleID: "com.example.app", title: "Same", x: 20),
        ]

        let items = MenuBarItemAXProvider.assemble(raw)

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(Set(items.map(\.uniqueIdentifier)).count, 3)
    }

    func testAssembleSkipsNativeOverflowPlaceholder() {
        let raw = [
            rawItem(namespace: .menuBarAgent, title: "Real", x: 0),
            MenuBarItemAXProvider.RawItem(
                namespace: .menuBarAgent,
                identityTitle: "<",
                displayTitle: "<",
                bounds: CGRect(x: 100, y: 0, width: 20, height: 22),
                ownerPID: 1234
            ),
        ]

        let items = MenuBarItemAXProvider.assemble(raw)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "Real")
    }

    func testAssembleSortsLeftToRight() {
        let raw = [
            rawItem(bundleID: "com.example.a", title: "A", x: 100),
            rawItem(bundleID: "com.example.b", title: "B", x: 50),
            rawItem(bundleID: "com.example.c", title: "C", x: 200),
        ]

        let items = MenuBarItemAXProvider.assemble(raw)

        XCTAssertEqual(items.map(\.title), ["B", "A", "C"])
    }

    func testAssembleSyntheticWindowIDStable() {
        let raw = [rawItem(bundleID: "com.example.app", title: "Stable", x: 0)]

        let first = MenuBarItemAXProvider.assemble(raw)
        let second = MenuBarItemAXProvider.assemble(raw)

        XCTAssertEqual(first.first?.windowID, second.first?.windowID)
    }

    func testAssembleFallbackTitleBump() {
        let raw = [
            rawItem(bundleID: "com.example.app", title: "Item-0", x: 0),
        ]

        let items = MenuBarItemAXProvider.assemble(raw)

        XCTAssertEqual(items.first?.title, "Item-0")
    }

    func testAssembleDropsMenuBarAgentRevendAtSamePosition() {
        // macOS 27 vends the same physical item twice: once under the app and
        // once under MenuBarAgent, at the same on-screen position.
        let raw = [
            rawItem(bundleID: "com.example.app", title: "Metric", x: 200),
            rawItem(namespace: .menuBarAgent, title: "Metric", x: 200),
        ]

        let items = MenuBarItemAXProvider.assemble(raw)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.tag.namespace, .string("com.example.app"))
    }

    func testAssembleKeepsMenuBarAgentOnlyItem() {
        // A genuine system item vended only by MenuBarAgent (no direct-app
        // twin) must survive the dedup.
        let raw = [
            rawItem(bundleID: "com.example.app", title: "Metric", x: 200),
            rawItem(namespace: .menuBarAgent, title: "Clock", x: 500),
        ]

        let items = MenuBarItemAXProvider.assemble(raw)

        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.contains { $0.title == "Clock" })
        XCTAssertTrue(items.contains { $0.title == "Metric" })
    }

    func testAssembleKeepsDistinctItemsAtDifferentPositions() {
        // A MenuBarAgent entry at a different position from the direct-app
        // entry is a distinct item and must be preserved.
        let raw = [
            rawItem(bundleID: "com.example.app", title: "Metric", x: 200),
            rawItem(namespace: .menuBarAgent, title: "Metric", x: 260),
        ]

        let items = MenuBarItemAXProvider.assemble(raw)

        XCTAssertEqual(items.count, 2)
    }

    func testDropDuplicateMenuBarAgentRevendsWithinTolerance() {
        // Sub-point positional jitter between the two vends still dedups.
        let raw = [
            rawItem(bundleID: "com.example.app", title: "Metric", x: 200),
            rawItem(namespace: .menuBarAgent, title: "Metric", x: 200.5),
        ].sorted { $0.bounds.minX < $1.bounds.minX }

        let deduped = MenuBarItemAXProvider.dropDuplicateMenuBarAgentRevends(raw)

        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped.first?.namespace, .string("com.example.app"))
    }

    func testAssembleKeepsItemsAtSameHorizontalPositionOnStackedDisplays() {
        let raw = [
            rawItem(bundleID: "com.example.app", title: "Metric", x: 200, y: 0),
            rawItem(namespace: .menuBarAgent, title: "Clock", x: 200, y: 1080),
        ]

        let items = MenuBarItemAXProvider.assemble(raw)

        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.contains { $0.title == "Metric" })
        XCTAssertTrue(items.contains { $0.title == "Clock" })
    }

    func testFrameIsWithinDisplayWhenMidpointFallsInsideBounds() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        XCTAssertTrue(
            MenuBarItemAXProvider.frame(
                CGRect(x: 100, y: 0, width: 24, height: 22),
                isWithin: displayBounds
            )
        )
    }

    func testFrameIsNotWithinDisplayWhenMidpointFallsOutsideBounds() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        XCTAssertFalse(
            MenuBarItemAXProvider.frame(
                CGRect(x: 2000, y: 0, width: 24, height: 22),
                isWithin: displayBounds
            )
        )
    }

    func testFrameOnSecondDisplayIsNotAttributedToFirstDisplay() {
        // Two side-by-side displays: primary at x∈[0, 1920), secondary at
        // x∈[1920, 3840). An item on the secondary display must not be
        // filtered into the primary display's item list.
        let primaryDisplayBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let secondaryItemFrame = CGRect(x: 1950, y: 0, width: 24, height: 22)

        XCTAssertFalse(
            MenuBarItemAXProvider.frame(secondaryItemFrame, isWithin: primaryDisplayBounds)
        )
    }

    private func rawItem(
        bundleID: String,
        title: String,
        x: CGFloat,
        y: CGFloat = 0
    ) -> MenuBarItemAXProvider.RawItem {
        rawItem(namespace: .string(bundleID), title: title, x: x, y: y)
    }

    private func rawItem(
        namespace: MenuBarItemTag.Namespace,
        title: String,
        x: CGFloat,
        y: CGFloat = 0
    ) -> MenuBarItemAXProvider.RawItem {
        MenuBarItemAXProvider.RawItem(
            namespace: namespace,
            identityTitle: title,
            displayTitle: title,
            bounds: CGRect(x: x, y: y, width: 20, height: 22),
            ownerPID: 1234
        )
    }
}
