//
//  AdvancedSettingsSnapshotTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers ``AdvancedSettingsSnapshot``'s value semantics and `Codable`
/// conformance. A profile from an older build can miss any key, so decoding
/// falls back to `Defaults.DefaultValue` instead of throwing.
@Suite("Advanced settings snapshot")
struct AdvancedSettingsSnapshotTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Helper Methods

    private func makeDefaultSnapshot() -> AdvancedSettingsSnapshot {
        AdvancedSettingsSnapshot(
            enableAlwaysHiddenSection: true,
            showAllSectionsOnUserDrag: true,
            sectionDividerStyle: 0,
            hideApplicationMenus: false,
            enableSecondaryContextMenu: true,
            enableSecondaryContextMenuQuit: false,
            showOnHoverDelay: 0.2,
            tooltipDelay: 1.0,
            showMenuBarTooltips: true,
            iconRefreshInterval: 3.0,
            useDoubleClickToShowAlwaysHiddenSection: false,
            useOptionClickToShowAlwaysHiddenSection: false,
            enableMenuBarItemOverflow: false,
            searchSectionOrder: ["visible", "hidden", "alwaysHidden"],
            searchIncludeVisible: true,
            searchIncludeHidden: true,
            searchIncludeAlwaysHidden: true
        )
    }

    private func makeCustomSnapshot() -> AdvancedSettingsSnapshot {
        AdvancedSettingsSnapshot(
            enableAlwaysHiddenSection: false,
            showAllSectionsOnUserDrag: false,
            sectionDividerStyle: 1,
            hideApplicationMenus: true,
            enableSecondaryContextMenu: false,
            enableSecondaryContextMenuQuit: true,
            showOnHoverDelay: 0.5,
            tooltipDelay: 2.0,
            showMenuBarTooltips: false,
            iconRefreshInterval: 5.0,
            useDoubleClickToShowAlwaysHiddenSection: true,
            useOptionClickToShowAlwaysHiddenSection: true,
            enableMenuBarItemOverflow: true,
            searchSectionOrder: ["alwaysHidden", "hidden", "visible"],
            searchIncludeVisible: false,
            searchIncludeHidden: true,
            searchIncludeAlwaysHidden: false
        )
    }

    // MARK: - Initialization Tests

    @Test("A snapshot keeps the default values it was built with")
    func defaultSnapshotValues() {
        let snapshot = makeDefaultSnapshot()

        #expect(snapshot.enableAlwaysHiddenSection)
        #expect(snapshot.showAllSectionsOnUserDrag)
        #expect(snapshot.sectionDividerStyle == 0)
        #expect(!snapshot.hideApplicationMenus)
        #expect(snapshot.enableSecondaryContextMenu)
        #expect(snapshot.showOnHoverDelay == 0.2)
        #expect(snapshot.tooltipDelay == 1.0)
        #expect(snapshot.showMenuBarTooltips)
        #expect(snapshot.iconRefreshInterval == 3.0)
        #expect(!snapshot.useDoubleClickToShowAlwaysHiddenSection)
    }

    @Test("A snapshot keeps the custom values it was built with")
    func customSnapshotValues() {
        let snapshot = makeCustomSnapshot()

        #expect(!snapshot.enableAlwaysHiddenSection)
        #expect(!snapshot.showAllSectionsOnUserDrag)
        #expect(snapshot.sectionDividerStyle == 1)
        #expect(snapshot.hideApplicationMenus)
        #expect(!snapshot.enableSecondaryContextMenu)
        #expect(snapshot.showOnHoverDelay == 0.5)
        #expect(snapshot.tooltipDelay == 2.0)
        #expect(!snapshot.showMenuBarTooltips)
        #expect(snapshot.iconRefreshInterval == 5.0)
        #expect(snapshot.useDoubleClickToShowAlwaysHiddenSection)
    }

    // MARK: - Encode/Decode Tests

    @Test("A default snapshot survives a round trip unchanged")
    func encodeDecodeDefaultSnapshot() throws {
        let original = makeDefaultSnapshot()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

        #expect(decoded.enableAlwaysHiddenSection == original.enableAlwaysHiddenSection)
        #expect(decoded.showAllSectionsOnUserDrag == original.showAllSectionsOnUserDrag)
        #expect(decoded.sectionDividerStyle == original.sectionDividerStyle)
        #expect(decoded.hideApplicationMenus == original.hideApplicationMenus)
        #expect(decoded.enableSecondaryContextMenu == original.enableSecondaryContextMenu)
        #expect(decoded.showOnHoverDelay == original.showOnHoverDelay)
        #expect(decoded.tooltipDelay == original.tooltipDelay)
        #expect(decoded.showMenuBarTooltips == original.showMenuBarTooltips)
        #expect(decoded.iconRefreshInterval == original.iconRefreshInterval)
        #expect(decoded.useDoubleClickToShowAlwaysHiddenSection == original.useDoubleClickToShowAlwaysHiddenSection)
    }

    @Test("A custom snapshot survives a round trip unchanged")
    func encodeDecodeCustomSnapshot() throws {
        let original = makeCustomSnapshot()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

        #expect(decoded.enableAlwaysHiddenSection == false)
        #expect(decoded.showAllSectionsOnUserDrag == false)
        #expect(decoded.sectionDividerStyle == 1)
        #expect(decoded.hideApplicationMenus == true)
        #expect(decoded.enableSecondaryContextMenu == false)
        #expect(decoded.showOnHoverDelay == 0.5)
        #expect(decoded.tooltipDelay == 2.0)
        #expect(decoded.showMenuBarTooltips == false)
        #expect(decoded.iconRefreshInterval == 5.0)
        #expect(decoded.useDoubleClickToShowAlwaysHiddenSection == true)
    }

    // MARK: - Forward-Compatibility Tests

    @Test("A profile written before the newer keys existed decodes with their defaults")
    func decodeOlderProfileMissingNewerKeys() throws {
        // A profile saved before useDoubleClickToShowAlwaysHiddenSection and
        // enableSecondaryContextMenuQuit existed; they decode to defaults.
        let json = """
        {
            "enableAlwaysHiddenSection": true,
            "showAllSectionsOnUserDrag": false,
            "sectionDividerStyle": 0,
            "hideApplicationMenus": true,
            "enableSecondaryContextMenu": true,
            "showOnHoverDelay": 0.2,
            "tooltipDelay": 1.0,
            "showMenuBarTooltips": false,
            "iconRefreshInterval": 3.0,
            "enableDiagnosticLogging": false
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: json)

        #expect(decoded.enableAlwaysHiddenSection)
        #expect(
            decoded.useDoubleClickToShowAlwaysHiddenSection
                == Defaults.DefaultValue.useDoubleClickToShowAlwaysHiddenSection
        )
        #expect(
            decoded.enableSecondaryContextMenuQuit
                == Defaults.DefaultValue.enableSecondaryContextMenuQuit
        )
    }

    @Test("An empty object decodes to the shipped defaults")
    func decodeEmptyObjectFallsBackToDefaults() throws {
        // Worst-case forward-compat: every key is missing, decoder must still
        // produce a snapshot rather than throwing keyNotFound.
        let json = "{}".data(using: .utf8)!
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: json)

        #expect(
            decoded.enableAlwaysHiddenSection
                == Defaults.DefaultValue.enableAlwaysHiddenSection
        )
        #expect(
            decoded.sectionDividerStyle
                == Defaults.DefaultValue.sectionDividerStyle.rawValue
        )
        #expect(
            decoded.enableSecondaryContextMenuQuit
                == Defaults.DefaultValue.enableSecondaryContextMenuQuit
        )
    }

    // MARK: - SectionDividerStyle Tests

    @Test("Every section divider style survives a round trip")
    func allSectionDividerStyles() throws {
        for style in SectionDividerStyle.allCases {
            var snapshot = makeDefaultSnapshot()
            snapshot.sectionDividerStyle = style.rawValue

            let data = try encoder.encode(snapshot)
            let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

            #expect(decoded.sectionDividerStyle == style.rawValue)
        }
    }

    // MARK: - TimeInterval Edge Cases

    @Test("A zero hover delay round-trips")
    func zeroShowOnHoverDelay() throws {
        var snapshot = makeDefaultSnapshot()
        snapshot.showOnHoverDelay = 0

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

        #expect(decoded.showOnHoverDelay == 0)
    }

    @Test("A large hover delay round-trips")
    func largeShowOnHoverDelay() throws {
        var snapshot = makeDefaultSnapshot()
        snapshot.showOnHoverDelay = 10.0

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

        #expect(decoded.showOnHoverDelay == 10.0)
    }

    @Test("A zero tooltip delay round-trips")
    func zeroTooltipDelay() throws {
        var snapshot = makeDefaultSnapshot()
        snapshot.tooltipDelay = 0

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

        #expect(decoded.tooltipDelay == 0)
    }

    @Test("A large tooltip delay round-trips")
    func largeTooltipDelay() throws {
        var snapshot = makeDefaultSnapshot()
        snapshot.tooltipDelay = 60.0

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

        #expect(decoded.tooltipDelay == 60.0)
    }

    @Test("A zero icon refresh interval round-trips")
    func zeroIconRefreshInterval() throws {
        var snapshot = makeDefaultSnapshot()
        snapshot.iconRefreshInterval = 0

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

        #expect(decoded.iconRefreshInterval == 0)
    }

    @Test("A large icon refresh interval round-trips")
    func largeIconRefreshInterval() throws {
        var snapshot = makeDefaultSnapshot()
        snapshot.iconRefreshInterval = 60.0

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

        #expect(decoded.iconRefreshInterval == 60.0)
    }

    @Test("Fractional delays round-trip within tolerance")
    func fractionalDelays() throws {
        var snapshot = makeDefaultSnapshot()
        snapshot.showOnHoverDelay = 0.15
        snapshot.tooltipDelay = 0.75
        snapshot.iconRefreshInterval = 2.5

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

        #expect(abs(decoded.showOnHoverDelay - 0.15) < 0.001)
        #expect(abs(decoded.tooltipDelay - 0.75) < 0.001)
        #expect(abs(decoded.iconRefreshInterval - 2.5) < 0.001)
    }

    // MARK: - Boolean Combinations

    @Test("A snapshot with every boolean off round-trips")
    func allBooleansFalse() throws {
        let snapshot = AdvancedSettingsSnapshot(
            enableAlwaysHiddenSection: false,
            showAllSectionsOnUserDrag: false,
            sectionDividerStyle: 0,
            hideApplicationMenus: false,
            enableSecondaryContextMenu: false,
            enableSecondaryContextMenuQuit: false,
            showOnHoverDelay: 0,
            tooltipDelay: 0,
            showMenuBarTooltips: false,
            iconRefreshInterval: 0,
            useDoubleClickToShowAlwaysHiddenSection: false,
            useOptionClickToShowAlwaysHiddenSection: false,
            enableMenuBarItemOverflow: false,
            searchSectionOrder: ["visible", "hidden", "alwaysHidden"],
            searchIncludeVisible: false,
            searchIncludeHidden: false,
            searchIncludeAlwaysHidden: false
        )

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

        #expect(!decoded.enableAlwaysHiddenSection)
        #expect(!decoded.showAllSectionsOnUserDrag)
        #expect(!decoded.hideApplicationMenus)
        #expect(!decoded.enableSecondaryContextMenu)
        #expect(!decoded.enableSecondaryContextMenuQuit)
        #expect(!decoded.showMenuBarTooltips)
        #expect(!decoded.useDoubleClickToShowAlwaysHiddenSection)
        #expect(!decoded.searchIncludeVisible)
        #expect(!decoded.searchIncludeHidden)
        #expect(!decoded.searchIncludeAlwaysHidden)
    }

    @Test("A snapshot with every boolean on round-trips")
    func allBooleansTrue() throws {
        let snapshot = AdvancedSettingsSnapshot(
            enableAlwaysHiddenSection: true,
            showAllSectionsOnUserDrag: true,
            sectionDividerStyle: 0,
            hideApplicationMenus: true,
            enableSecondaryContextMenu: true,
            enableSecondaryContextMenuQuit: true,
            showOnHoverDelay: 0,
            tooltipDelay: 0,
            showMenuBarTooltips: true,
            iconRefreshInterval: 0,
            useDoubleClickToShowAlwaysHiddenSection: true,
            useOptionClickToShowAlwaysHiddenSection: true,
            enableMenuBarItemOverflow: true,
            searchSectionOrder: ["visible", "hidden", "alwaysHidden"],
            searchIncludeVisible: true,
            searchIncludeHidden: true,
            searchIncludeAlwaysHidden: true
        )

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

        #expect(decoded.enableAlwaysHiddenSection)
        #expect(decoded.showAllSectionsOnUserDrag)
        #expect(decoded.hideApplicationMenus)
        #expect(decoded.enableSecondaryContextMenu)
        #expect(decoded.enableSecondaryContextMenuQuit)
        #expect(decoded.showMenuBarTooltips)
        #expect(decoded.useDoubleClickToShowAlwaysHiddenSection)
        #expect(decoded.searchIncludeVisible)
        #expect(decoded.searchIncludeHidden)
        #expect(decoded.searchIncludeAlwaysHidden)
    }

    // MARK: - Search Section Ordering

    @Test("The search section order and its filters round-trip")
    func searchSectionOrderRoundTrip() throws {
        var snapshot = makeDefaultSnapshot()
        snapshot.searchSectionOrder = ["alwaysHidden", "hidden", "visible"]
        snapshot.searchIncludeVisible = false

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

        #expect(decoded.searchSectionOrder == ["alwaysHidden", "hidden", "visible"])
        #expect(!decoded.searchIncludeVisible)
        #expect(decoded.searchIncludeHidden)
        #expect(decoded.searchIncludeAlwaysHidden)
    }

    @Test("A profile written before the search keys existed decodes with their defaults")
    func decodeProfileMissingSearchKeysFallsBackToDefaults() throws {
        // Simulates a profile saved before the search-ordering fields were added.
        let json = """
        {
            "enableAlwaysHiddenSection": true,
            "showAllSectionsOnUserDrag": false,
            "sectionDividerStyle": 0,
            "hideApplicationMenus": true,
            "enableSecondaryContextMenu": true,
            "showOnHoverDelay": 0.2,
            "tooltipDelay": 1.0,
            "showMenuBarTooltips": false,
            "iconRefreshInterval": 3.0,
            "enableDiagnosticLogging": false
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: json)

        #expect(decoded.searchSectionOrder == Defaults.DefaultValue.searchSectionOrder)
        #expect(decoded.searchIncludeVisible == Defaults.DefaultValue.searchIncludeVisible)
        #expect(decoded.searchIncludeHidden == Defaults.DefaultValue.searchIncludeHidden)
        #expect(decoded.searchIncludeAlwaysHidden == Defaults.DefaultValue.searchIncludeAlwaysHidden)
        #expect(decoded.moveCursorToRevealedItem == Defaults.DefaultValue.moveCursorToRevealedItem)
    }

    @Test("The pointer-move setting round-trips")
    func moveCursorToRevealedItemRoundTrip() throws {
        var snapshot = makeDefaultSnapshot()
        snapshot.moveCursorToRevealedItem = true

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

        #expect(decoded.moveCursorToRevealedItem)
    }

    // MARK: - Diagnostic Logging Exclusion

    /// `enableDiagnosticLogging` is deliberately not part of a profile.
    ///
    /// Applying a profile restored the saved switch state, usually off, so
    /// logging stopped right when a user turned it on to capture a profile
    /// switch (#899).
    @Test("A profile written before the removal still decodes, ignoring the key")
    func legacyDiagnosticLoggingKeyIsIgnored() throws {
        let json = """
        {
            "enableAlwaysHiddenSection": true,
            "showAllSectionsOnUserDrag": false,
            "sectionDividerStyle": 0,
            "hideApplicationMenus": true,
            "enableSecondaryContextMenu": true,
            "showOnHoverDelay": 0.2,
            "tooltipDelay": 1.0,
            "showMenuBarTooltips": false,
            "iconRefreshInterval": 3.0,
            "enableDiagnosticLogging": true
        }
        """.data(using: .utf8)!

        // Decoding must not throw on the now-unknown key, and the rest of the
        // snapshot must come through intact.
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: json)

        #expect(decoded.enableAlwaysHiddenSection)
        #expect(decoded.hideApplicationMenus)
        #expect(decoded.iconRefreshInterval == 3.0)
    }

    /// A profile saved by this build carries no diagnostic-logging state, so
    /// applying it on any build, older ones included, can't disturb the switch.
    @Test("An encoded snapshot no longer writes the key")
    func encodedSnapshotOmitsDiagnosticLogging() throws {
        let data = try encoder.encode(makeCustomSnapshot())
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(!json.contains("enableDiagnosticLogging"))
    }
}
