//
//  ProfileSnapshotCodableTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Missing keys use Defaults.DefaultValue per field so older profiles remain readable.
/// Pin fallback behavior and encoded keys to preserve the wire contract across Codable changes.
@Suite("Profile snapshot Codable")
struct ProfileSnapshotCodableTests {
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    // MARK: Round trip

    @Test("A non-default general snapshot survives a JSON round trip")
    func generalSnapshotRoundTrips() throws {
        let data = try encoder.encode(Self.generalSnapshot())
        let decoded = try decoder.decode(GeneralSettingsSnapshot.self, from: data)
        let reencoded = try encoder.encode(decoded)

        #expect(reencoded == data)
    }

    @Test("A non-default advanced snapshot survives a JSON round trip")
    func advancedSnapshotRoundTrips() throws {
        let data = try encoder.encode(Self.advancedSnapshot())
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)
        let reencoded = try encoder.encode(decoded)

        #expect(reencoded == data)
    }

    // MARK: Missing keys

    @Test("A general snapshot missing keys falls back to the documented defaults")
    func generalSnapshotFillsMissingKeys() throws {
        // Ignore unsupported showOnDoubleClick keys when decoding profiles.
        let json = Data(#"{"showIceIcon": false, "iceBarLocation": 1, "rehideInterval": 42, "showOnDoubleClick": false}"#.utf8)

        let snapshot = try decoder.decode(GeneralSettingsSnapshot.self, from: json)

        #expect(snapshot.showThawIcon == false)
        #expect(snapshot.thawBarLocation == .mousePointer)
        #expect(snapshot.rehideInterval == 42)

        #expect(snapshot.thawIcon == Defaults.DefaultValue.thawIcon)
        #expect(snapshot.lastCustomThawIcon == nil)
        #expect(snapshot.customThawIconIsTemplate == Defaults.DefaultValue.customThawIconIsTemplate)
        #expect(snapshot.useThawBar == Defaults.DefaultValue.useThawBar)
        #expect(snapshot.useThawBarOnlyOnNotchedDisplay == Defaults.DefaultValue.useThawBarOnlyOnNotchedDisplay)
        #expect(snapshot.thawBarLocationOnHotkey == Defaults.DefaultValue.thawBarLocationOnHotkey)
        #expect(snapshot.showOnClick == Defaults.DefaultValue.showOnClick)
        #expect(snapshot.showOnHover == Defaults.DefaultValue.showOnHover)
        #expect(snapshot.showOnScroll == Defaults.DefaultValue.showOnScroll)
        #expect(snapshot.autoRehide == Defaults.DefaultValue.autoRehide)
        #expect(snapshot.rehideStrategyRawValue == Defaults.DefaultValue.rehideStrategy.rawValue)
        #expect(snapshot.tempShowInterval == Defaults.DefaultValue.tempShowInterval)
    }

    @Test("An advanced snapshot missing keys falls back to the documented defaults")
    func advancedSnapshotFillsMissingKeys() throws {
        let json = Data(#"{"sectionDividerStyle": 1, "searchIncludeVisible": false}"#.utf8)

        let snapshot = try decoder.decode(AdvancedSettingsSnapshot.self, from: json)

        #expect(snapshot.sectionDividerStyle == 1)
        #expect(snapshot.searchIncludeVisible == false)

        #expect(snapshot.enableAlwaysHiddenSection == Defaults.DefaultValue.enableAlwaysHiddenSection)
        #expect(snapshot.showAllSectionsOnUserDrag == Defaults.DefaultValue.showAllSectionsOnUserDrag)
        #expect(snapshot.hideApplicationMenus == Defaults.DefaultValue.hideApplicationMenus)
        #expect(snapshot.enableSecondaryContextMenu == Defaults.DefaultValue.enableSecondaryContextMenu)
        #expect(snapshot.showOnHoverDelay == Defaults.DefaultValue.showOnHoverDelay)
        #expect(snapshot.tooltipDelay == Defaults.DefaultValue.tooltipDelay)
        #expect(snapshot.showMenuBarTooltips == Defaults.DefaultValue.showMenuBarTooltips)
        #expect(snapshot.iconRefreshInterval == Defaults.DefaultValue.iconRefreshInterval)
        #expect(snapshot.menuBarItemAlertRevealCooldown == Defaults.DefaultValue.menuBarItemAlertRevealCooldown)
        #expect(snapshot.autoZenWhileSharingScreen == Defaults.DefaultValue.autoZenWhileSharingScreen)
        #expect(snapshot.enableDiagnosticLogging == Defaults.DefaultValue.enableDiagnosticLogging)
        #expect(snapshot.enableMenuBarItemOverflow == Defaults.DefaultValue.enableMenuBarItemOverflow)
        #expect(snapshot.enableExperimentalSystemItemHiding == Defaults.DefaultValue.enableExperimentalSystemItemHiding)
        #expect(snapshot.searchSectionOrder == Defaults.DefaultValue.searchSectionOrder)
        #expect(snapshot.searchIncludeHidden == Defaults.DefaultValue.searchIncludeHidden)
        #expect(snapshot.searchIncludeAlwaysHidden == Defaults.DefaultValue.searchIncludeAlwaysHidden)
    }

    // MARK: Encoded key set

    @Test("The general snapshot keeps its pinned Ice-era key set")
    func generalSnapshotKeySet() throws {
        let keys = try encodedKeys(of: Self.generalSnapshot())

        #expect(keys == [
            "autoRehide",
            "customIceIconIsTemplate",
            "iceBarLocation",
            "iceBarLocationOnHotkey",
            "iceIcon",
            "lastCustomIceIcon",
            "rehideInterval",
            "rehideStrategyRawValue",
            "showIceIcon",
            "showOnClick",
            "showOnHover",
            "showOnScroll",
            "tempShowInterval",
            "useIceBar",
            "useIceBarOnlyOnNotchedDisplay",
        ])
    }

    @Test("The advanced snapshot keeps its key set")
    func advancedSnapshotKeySet() throws {
        let keys = try encodedKeys(of: Self.advancedSnapshot())

        #expect(keys == [
            "autoZenWhileSharingScreen",
            "enableAlwaysHiddenSection",
            "enableDiagnosticLogging",
            "enableExperimentalSystemItemHiding",
            "enableMenuBarItemOverflow",
            "enableSecondaryContextMenu",
            "hideApplicationMenus",
            "iconRefreshInterval",
            "menuBarItemAlertRevealCooldown",
            "searchIncludeAlwaysHidden",
            "searchIncludeHidden",
            "searchIncludeVisible",
            "searchSectionOrder",
            "sectionDividerStyle",
            "showAllSectionsOnUserDrag",
            "showMenuBarTooltips",
            "showOnHoverDelay",
            "tooltipDelay",
        ])
    }

    // MARK: Fixtures

    /// Non-default fields expose dropped keys in the re-encoded comparison.
    private static func generalSnapshot() -> GeneralSettingsSnapshot {
        GeneralSettingsSnapshot(
            showThawIcon: false,
            thawIcon: alternateIcon,
            lastCustomThawIcon: customIcon,
            customThawIconIsTemplate: true,
            useThawBar: true,
            useThawBarOnlyOnNotchedDisplay: true,
            thawBarLocation: .mousePointer,
            thawBarLocationOnHotkey: true,
            showOnClick: false,
            showOnHover: true,
            showOnScroll: false,
            autoRehide: false,
            rehideStrategyRawValue: RehideStrategy.timed.rawValue,
            rehideInterval: 42,
            tempShowInterval: 7
        )
    }

    private static func advancedSnapshot() -> AdvancedSettingsSnapshot {
        AdvancedSettingsSnapshot(
            enableAlwaysHiddenSection: true,
            showAllSectionsOnUserDrag: false,
            sectionDividerStyle: SectionDividerStyle.chevron.rawValue,
            hideApplicationMenus: false,
            enableSecondaryContextMenu: false,
            showOnHoverDelay: 1.5,
            tooltipDelay: 2.5,
            showMenuBarTooltips: true,
            iconRefreshInterval: 3.5,
            menuBarItemAlertRevealCooldown: 4.5,
            autoZenWhileSharingScreen: true,
            enableDiagnosticLogging: false,
            enableMenuBarItemOverflow: false,
            enableExperimentalSystemItemHiding: true,
            searchSectionOrder: ["hidden", "visible"],
            searchIncludeVisible: false,
            searchIncludeHidden: false,
            searchIncludeAlwaysHidden: false
        )
    }

    private static let alternateIcon = ControlItemImageSet(
        name: .arrow,
        hidden: .symbol("arrowshape.left.fill"),
        visible: .symbol("arrowshape.right.fill")
    )

    private static let customIcon = ControlItemImageSet(
        name: .dot,
        hidden: .catalog("DotFill"),
        visible: .catalog("DotStroke")
    )

    private func encodedKeys(of value: some Encodable) throws -> [String] {
        let data = try encoder.encode(value)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return object.keys.sorted()
    }
}
