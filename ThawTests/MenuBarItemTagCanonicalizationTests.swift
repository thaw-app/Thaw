//
//  MenuBarItemTagCanonicalizationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

// MARK: - Volatile-Title Canonicalization Tests

final class MenuBarItemTagCanonicalizationTests: XCTestCase {
    private let prefix = MenuBarItemTag.iStatMenusStatusBundleID

    // MARK: - canonicalMetricTitle

    func testCollapsesIntegersAndDecimals() {
        XCTAssertEqual(MenuBarItemTag.canonicalMetricTitle("CPU 12%"), "CPU #%")
        XCTAssertEqual(MenuBarItemTag.canonicalMetricTitle("CPU 43%"), "CPU #%")
        XCTAssertEqual(MenuBarItemTag.canonicalMetricTitle("Load 1.75"), "Load #")
        XCTAssertEqual(MenuBarItemTag.canonicalMetricTitle("Load 1,75"), "Load #")
        XCTAssertEqual(MenuBarItemTag.canonicalMetricTitle("Temp -4°"), "Temp #°")
    }

    /// The point of the unit normalization: a rate that crosses a magnitude
    /// boundary must not re-key the item.
    func testNormalizesByteUnitsAcrossMagnitudes() {
        let fast = MenuBarItemTag.canonicalMetricTitle("3.4 MB/s")
        let slow = MenuBarItemTag.canonicalMetricTitle("918 KB/s")
        XCTAssertEqual(fast, slow)

        XCTAssertEqual(
            MenuBarItemTag.canonicalMetricTitle("12 GB"),
            MenuBarItemTag.canonicalMetricTitle("512 MB")
        )
    }

    func testLeavesNonNumericTitlesDistinguishable() {
        XCTAssertEqual(MenuBarItemTag.canonicalMetricTitle("CPU"), "CPU")
        XCTAssertNotEqual(
            MenuBarItemTag.canonicalMetricTitle("CPU 12%"),
            MenuBarItemTag.canonicalMetricTitle("Network 12%")
        )
    }

    // MARK: - canonicalPersistentIdentifier

    func testIsANoOpForOtherOwners() {
        for identifier in [
            "com.apple.controlcenter:WiFi",
            "com.example.app:Battery 42%",
            "controlCenter:Item-3:1",
            "",
        ] {
            XCTAssertEqual(MenuBarItemTag.canonicalPersistentIdentifier(identifier), identifier)
        }
    }

    func testCollapsesSamplesOfTheSameItem() {
        let first = MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):CPU 12%")
        let second = MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):CPU 43%")

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, "\(prefix):CPU #%")
    }

    func testPreservesInstanceIndex() {
        XCTAssertEqual(
            MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):CPU 12%:2"),
            "\(prefix):CPU #%:2"
        )
        // Distinct instances of the same metric stay distinct.
        XCTAssertNotEqual(
            MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):CPU 12%:2"),
            MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):CPU 12%:3")
        )
    }

    /// A colon-bearing title whose trailing segment is not a number is part of
    /// the title, not an instance index.
    func testTreatsNonNumericTrailingSegmentAsTitle() {
        XCTAssertEqual(
            MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):Disk:Macintosh HD 88%"),
            "\(prefix):Disk:Macintosh HD #%"
        )
    }

    func testIsIdempotent() {
        let once = MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):Net 3.4 MB/s")
        let twice = MenuBarItemTag.canonicalPersistentIdentifier(once)
        XCTAssertEqual(once, twice)
    }

    // MARK: - canonicalPersistentIdentifiers

    func testDedupesVolatileDuplicatesPreservingOrder() {
        let result = MenuBarItemTag.canonicalPersistentIdentifiers([
            "com.apple.controlcenter:WiFi",
            "\(prefix):CPU 12%",
            "\(prefix):CPU 43%",
            "\(prefix):Net 918 KB/s",
            "com.example.app:Clock",
        ])

        XCTAssertEqual(result, [
            "com.apple.controlcenter:WiFi",
            "\(prefix):CPU #%",
            "\(prefix):Net # B/s",
            "com.example.app:Clock",
        ])
    }

    func testKeepsDistinctOwnersSeparate() {
        let result = MenuBarItemTag.canonicalPersistentIdentifiers([
            "\(prefix):CPU 12%",
            "\(prefix):Memory 12%",
        ])
        XCTAssertEqual(result.count, 2)
    }
}
