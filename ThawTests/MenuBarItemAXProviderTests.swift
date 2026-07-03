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

    private func rawItem(
        bundleID: String,
        title: String,
        x: CGFloat
    ) -> MenuBarItemAXProvider.RawItem {
        rawItem(namespace: .string(bundleID), title: title, x: x)
    }

    private func rawItem(
        namespace: MenuBarItemTag.Namespace,
        title: String,
        x: CGFloat
    ) -> MenuBarItemAXProvider.RawItem {
        MenuBarItemAXProvider.RawItem(
            namespace: namespace,
            identityTitle: title,
            displayTitle: title,
            bounds: CGRect(x: x, y: 0, width: 20, height: 22),
            ownerPID: 1234
        )
    }
}
