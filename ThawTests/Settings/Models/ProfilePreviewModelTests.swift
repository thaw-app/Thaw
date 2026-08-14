//
//  ProfilePreviewModelTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers the data shaping behind the profile preview popover: identifier
/// parsing and section assembly, which are split out of the view precisely so
/// they can be tested without standing up SwiftUI.
@Suite("Profile preview model")
struct ProfilePreviewModelTests {
    private func layout(
        savedSectionOrder: [String: [String]] = [:],
        customNames: [String: String] = [:],
        itemOrder: [String: [String]]? = nil
    ) -> MenuBarLayoutSnapshot {
        MenuBarLayoutSnapshot(
            savedSectionOrder: savedSectionOrder,
            pinnedHiddenBundleIDs: [],
            pinnedAlwaysHiddenBundleIDs: [],
            customNames: customNames,
            itemOrder: itemOrder
        )
    }

    // MARK: - split

    @Test("split separates the namespace from the title")
    func splitSeparatesNamespaceAndTitle() {
        let parsed = ProfilePreviewModel.split("com.example.app:Item Title")
        #expect(parsed.namespace == "com.example.app")
        #expect(parsed.title == "Item Title")
    }

    /// Titles may themselves contain colons, so only the first one divides.
    @Test("split divides on the first colon only")
    func splitDividesOnFirstColonOnly() {
        let parsed = ProfilePreviewModel.split("com.example.app:Title: With Colon")
        #expect(parsed.namespace == "com.example.app")
        #expect(parsed.title == "Title: With Colon")
    }

    /// Legacy `savedSectionOrder` entries are bare bundle IDs with no colon.
    @Test("split falls back to the whole identifier when there is no colon")
    func splitFallsBackToWholeIdentifier() {
        let parsed = ProfilePreviewModel.split("com.example.app")
        #expect(parsed.namespace == "com.example.app")
        #expect(parsed.title == "com.example.app")
    }

    // MARK: - sections

    @Test("Sections use the per-item order and apply custom names")
    func sectionsUseItemOrderAndCustomNames() {
        let snapshot = layout(
            savedSectionOrder: ["visible": ["legacy.app"]],
            customNames: ["com.example.app:Item": "Renamed"],
            itemOrder: ["visible": ["com.example.app:Item"], "hidden": ["com.other.app:Other"]]
        )
        let sections = ProfilePreviewModel.sections(for: snapshot)
        #expect(sections.map(\.key) == ["visible", "hidden", "alwaysHidden"])
        #expect(sections[0].items == [
            ProfilePreviewModel.Item(
                id: "com.example.app:Item",
                bundleID: "com.example.app",
                title: "Renamed"
            ),
        ])
        #expect(sections[1].items.map(\.title) == ["Other"])
        #expect(sections[2].items.isEmpty)
    }

    @Test("Sections fall back to the legacy order when itemOrder is missing")
    func sectionsFallBackToLegacyOrder() {
        let snapshot = layout(savedSectionOrder: ["visible": ["com.legacy.app"]])
        let sections = ProfilePreviewModel.sections(for: snapshot)
        #expect(sections[0].items.map(\.bundleID) == ["com.legacy.app"])
        #expect(sections[0].items.map(\.title) == ["com.legacy.app"])
    }

    /// A capture taken while the bar was still settling writes an empty
    /// `itemOrder` rather than omitting it. The preview has to read that as
    /// absent, the way the apply path does, or it shows an empty profile for
    /// one that has a perfectly good legacy order.
    @Test("An empty itemOrder falls back to the legacy order")
    func emptyItemOrderFallsBackToLegacyOrder() {
        let snapshot = layout(
            savedSectionOrder: ["visible": ["com.legacy.app"]],
            itemOrder: [:]
        )
        let sections = ProfilePreviewModel.sections(for: snapshot)
        #expect(sections[0].items.map(\.bundleID) == ["com.legacy.app"])
    }

    /// Sections are always reported in menu bar display order, including the
    /// ones a profile has nothing in.
    @Test("Every section is reported, empty or not")
    func everySectionIsReported() {
        let sections = ProfilePreviewModel.sections(for: layout())
        #expect(sections.map(\.key) == ["visible", "hidden", "alwaysHidden"])
        #expect(sections.flatMap(\.items).isEmpty)
    }

    // MARK: - spacing

    @Test("Spacing rows include the global value and named display overrides")
    func spacingRowsIncludeGlobalAndDisplayOverrides() {
        var profile = makeProfile(displayConfigurations: [
            "DISPLAY-B": .defaultConfiguration.withItemSpacingOffset(-3),
            "DISPLAY-A": .defaultConfiguration.withItemSpacingOffset(8),
        ])
        profile.globalDisplayConfiguration = .defaultConfiguration.withItemSpacingOffset(4)

        let rows = ProfilePreviewModel.spacingRows(
            for: profile,
            displayNames: ["DISPLAY-A": "Studio Display"]
        )

        #expect(rows == [
            .init(id: "global", displayName: nil, offset: 4),
            .init(id: "DISPLAY-B", displayName: "DISPLAY-B", offset: -3),
            .init(id: "DISPLAY-A", displayName: "Studio Display", offset: 8),
        ])
    }
}
