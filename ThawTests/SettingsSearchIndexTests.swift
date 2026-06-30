//
//  SettingsSearchIndexTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

// MARK: - SettingsSearchIndexTests

final class SettingsSearchIndexTests: XCTestCase {
    // MARK: - Index Integrity

    func testEntryIDsAreUnique() {
        let ids = SettingsSearchIndex.entries.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "SettingsSearchEntry ids must be unique")
    }

    func testEntriesAreNonEmpty() {
        for entry in SettingsSearchIndex.entries {
            XCTAssertFalse(entry.titleText.isEmpty, "\(entry.id) has an empty titleText")
        }
    }

    func testEveryPaneHasAtLeastOneEntry() {
        for pane in SettingsNavigationIdentifier.allCases {
            XCTAssertFalse(
                SettingsSearchIndex.entries(for: pane).isEmpty,
                "\(pane) has no search entries"
            )
        }
    }

    func testEntriesForPaneReturnsOnlyThatPane() {
        for pane in SettingsNavigationIdentifier.allCases {
            for entry in SettingsSearchIndex.entries(for: pane) {
                XCTAssertEqual(entry.pane, pane, "entries(for:) leaked a \(entry.pane) row into \(pane)")
            }
        }
    }

    func testPaneEntriesCoverAllNavigationIdentifiers() {
        let paneEntryPanes = Set(SettingsSearchIndex.entries.compactMap { $0.id.hasPrefix("pane.") ? $0.pane : nil })
        XCTAssertEqual(paneEntryPanes, Set(SettingsNavigationIdentifier.allCases))
    }

    // MARK: - Relevance Sort

    func testSortedByRelevanceOrdersLowestDiffScoreFirst() {
        let items: [(item: String, diffScore: Double)] = [
            ("worst", 0.9),
            ("best", 0.1),
            ("middle", 0.5),
        ]
        XCTAssertEqual(SettingsSearchIndex.sortedByRelevance(items), ["best", "middle", "worst"])
    }

    func testSortedByRelevanceHandlesEmptyInput() {
        let empty: [(item: String, diffScore: Double)] = []
        XCTAssertEqual(SettingsSearchIndex.sortedByRelevance(empty), [])
    }

    // MARK: - Drift Guard: @Published properties ↔ index entries

    @MainActor
    func testEveryPublishedGeneralSettingHasSearchEntry() {
        let settings = GeneralSettings()
        let published = Self.publishedPropertyNames(of: settings)
        XCTAssertFalse(published.isEmpty, "Expected to reflect @Published properties on GeneralSettings")

        for name in published {
            if SettingsSearchIndex.nonSearchableProperties.contains(.general(name)) {
                continue
            }
            let hasEntry = SettingsSearchIndex.entries.contains { $0.property == .general(name) }
            XCTAssertTrue(
                hasEntry,
                "GeneralSettings.\(name) has no SettingsSearchEntry. Add an entry or, if it is intentionally not searchable, add `.general(\"\(name)\")` to nonSearchableProperties."
            )
        }
    }

    @MainActor
    func testEveryPublishedAdvancedSettingHasSearchEntry() {
        let settings = AdvancedSettings()
        let published = Self.publishedPropertyNames(of: settings)
        XCTAssertFalse(published.isEmpty, "Expected to reflect @Published properties on AdvancedSettings")

        for name in published {
            if SettingsSearchIndex.nonSearchableProperties.contains(.advanced(name)) {
                continue
            }
            let hasEntry = SettingsSearchIndex.entries.contains { $0.property == .advanced(name) }
            XCTAssertTrue(
                hasEntry,
                "AdvancedSettings.\(name) has no SettingsSearchEntry. Add an entry or, if it is intentionally not searchable, add `.advanced(\"\(name)\")` to nonSearchableProperties."
            )
        }
    }

    @MainActor
    func testEntryPropertiesReferenceRealPublishedProperties() {
        let generalNames = Set(Self.publishedPropertyNames(of: GeneralSettings()))
        let advancedNames = Set(Self.publishedPropertyNames(of: AdvancedSettings()))

        for entry in SettingsSearchIndex.entries {
            guard let property = entry.property else { continue }
            switch property {
            case let .general(name):
                XCTAssertTrue(
                    generalNames.contains(name),
                    "Entry \(entry.id) references GeneralSettings.\(name), which does not exist."
                )
            case let .advanced(name):
                XCTAssertTrue(
                    advancedNames.contains(name),
                    "Entry \(entry.id) references AdvancedSettings.\(name), which does not exist."
                )
            }
        }
    }

    @MainActor
    func testNonSearchablePropertiesReferenceRealPublishedProperties() {
        // Every allowlisted exclusion must point at a real property, otherwise
        // a rename would silently let an entry go missing from the index.
        let generalNames = Set(Self.publishedPropertyNames(of: GeneralSettings()))
        let advancedNames = Set(Self.publishedPropertyNames(of: AdvancedSettings()))

        for property in SettingsSearchIndex.nonSearchableProperties {
            switch property {
            case let .general(name):
                XCTAssertTrue(generalNames.contains(name), "nonSearchableProperties lists GeneralSettings.\(name), which does not exist.")
            case let .advanced(name):
                XCTAssertTrue(advancedNames.contains(name), "nonSearchableProperties lists AdvancedSettings.\(name), which does not exist.")
            }
        }
    }

    // MARK: - Helpers

    /// Returns the labels of the `@Published` stored properties on `object`.
    /// `@Published` is a property wrapper, so Mirror reflects the synthesized
    /// `_foo` stored property (of type `Published<Value>`) rather than the
    /// computed `foo` accessor. The leading underscore is stripped so the
    /// returned names match the property names as written in source.
    private static func publishedPropertyNames(of object: some AnyObject) -> [String] {
        Mirror(reflecting: object).children.compactMap { child in
            guard
                let label = child.label,
                label.hasPrefix("_")
            else { return nil }
            let typeName = String(reflecting: type(of: child.value))
            guard typeName.contains("Published") else { return nil }
            return String(label.dropFirst())
        }
    }
}
