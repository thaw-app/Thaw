//
//  MenuBarItemTagCanonicalizationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

// MARK: - Volatile-Title Canonicalization Tests

@Suite("Menu bar item tag canonicalization")
struct MenuBarItemTagCanonicalizationTests {
    private let prefix = MenuBarItemTag.iStatMenusStatusBundleID

    // MARK: - canonicalMetricTitle

    @Test("Integers and decimals collapse to a placeholder")
    func collapsesIntegersAndDecimals() {
        #expect(MenuBarItemTag.canonicalMetricTitle("CPU 12%") == "CPU #%")
        #expect(MenuBarItemTag.canonicalMetricTitle("CPU 43%") == "CPU #%")
        #expect(MenuBarItemTag.canonicalMetricTitle("Load 1.75") == "Load #")
        #expect(MenuBarItemTag.canonicalMetricTitle("Load 1,75") == "Load #")
        #expect(MenuBarItemTag.canonicalMetricTitle("Temp -4°") == "Temp #°")
    }

    /// The point of the unit normalization: a rate that crosses a magnitude
    /// boundary must not re-key the item.
    @Test("Byte units normalize across magnitudes")
    func normalizesByteUnitsAcrossMagnitudes() {
        let fast = MenuBarItemTag.canonicalMetricTitle("3.4 MB/s")
        let slow = MenuBarItemTag.canonicalMetricTitle("918 KB/s")
        #expect(fast == slow)

        #expect(
            MenuBarItemTag.canonicalMetricTitle("12 GB")
                == MenuBarItemTag.canonicalMetricTitle("512 MB")
        )
    }

    @Test("Non-numeric titles stay distinguishable")
    func leavesNonNumericTitlesDistinguishable() {
        #expect(MenuBarItemTag.canonicalMetricTitle("CPU") == "CPU")
        #expect(
            MenuBarItemTag.canonicalMetricTitle("CPU 12%")
                != MenuBarItemTag.canonicalMetricTitle("Network 12%")
        )
    }

    // MARK: - canonicalPersistentIdentifier

    @Test("Identifiers owned by anything else are left alone")
    func isANoOpForOtherOwners() {
        for identifier in [
            "com.apple.controlcenter:WiFi",
            "com.example.app:Battery 42%",
            "controlCenter:Item-3:1",
            "",
        ] {
            #expect(MenuBarItemTag.canonicalPersistentIdentifier(identifier) == identifier)
        }
    }

    @Test("Samples of the same item collapse to one identifier")
    func collapsesSamplesOfTheSameItem() {
        let first = MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):CPU 12%")
        let second = MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):CPU 43%")

        #expect(first == second)
        #expect(first == "\(prefix):CPU #%")
    }

    @Test("The instance index survives canonicalization")
    func preservesInstanceIndex() {
        #expect(
            MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):CPU 12%:2")
                == "\(prefix):CPU #%:2"
        )
        // Distinct instances of the same metric stay distinct.
        #expect(
            MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):CPU 12%:2")
                != MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):CPU 12%:3")
        )
    }

    /// A colon-bearing title whose trailing segment is not a number is part of
    /// the title, not an instance index.
    @Test("A non-numeric trailing segment is treated as part of the title")
    func treatsNonNumericTrailingSegmentAsTitle() {
        #expect(
            MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):Disk:Macintosh HD 88%")
                == "\(prefix):Disk:Macintosh HD #%"
        )
    }

    @Test("Canonicalization is idempotent")
    func isIdempotent() {
        let once = MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):Net 3.4 MB/s")
        let twice = MenuBarItemTag.canonicalPersistentIdentifier(once)
        #expect(once == twice)
    }

    // MARK: - canonicalPersistentIdentifiers

    @Test("Volatile duplicates are deduped in order")
    func dedupesVolatileDuplicatesPreservingOrder() {
        let result = MenuBarItemTag.canonicalPersistentIdentifiers([
            "com.apple.controlcenter:WiFi",
            "\(prefix):CPU 12%",
            "\(prefix):CPU 43%",
            "\(prefix):Net 918 KB/s",
            "com.example.app:Clock",
        ])

        #expect(result == [
            "com.apple.controlcenter:WiFi",
            "\(prefix):CPU #%",
            "\(prefix):Net # B/s",
            "com.example.app:Clock",
        ])
    }

    @Test("Distinct owners stay separate")
    func keepsDistinctOwnersSeparate() {
        let result = MenuBarItemTag.canonicalPersistentIdentifiers([
            "\(prefix):CPU 12%",
            "\(prefix):Memory 12%",
        ])
        #expect(result.count == 2)
    }
}
