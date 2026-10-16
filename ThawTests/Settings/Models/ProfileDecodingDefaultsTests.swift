//
//  ProfileDecodingDefaultsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

// MARK: - Snapshot capture and apply

/// Covers `capture(from:)` and `apply(to:)` on `GeneralSettingsSnapshot` and
/// `AdvancedSettingsSnapshot`, the halves that talk to the live settings models.
///
/// Other snapshot suites only round-trip hand-built snapshots through JSON. A
/// property missing from `capture` silently reverts on the next profile switch;
/// one missing from `apply` silently keeps the previous profile's value.
///
/// `Defaults.store` is process-wide, so each case runs inside
/// `withScratchDefaults` and the suite is `.serialized`.
///
/// Deliberate gaps:
/// - `enableDiagnosticLogging` is no longer in the snapshot, since a profile
///   apply switched logging off mid-capture (#899). Old profiles' key is
///   ignored on decode.
/// - The models are built bare rather than through `performSetup()`.
///   `GeneralSettingsTests` and `AdvancedSettingsTests` own that path.
@MainActor
@Suite("Profile snapshots against live settings models", .serialized)
struct ProfileSnapshotLiveSettingsTests {
    /// A named icon that is *not* `.custom`, so assigning it to `iceIcon`
    /// leaves `lastCustomIceIcon` alone.
    private var namedIcon: ControlItemImageSet {
        ControlItemImageSet(name: .door, image: .symbol("door.left.hand.closed"))
    }

    /// An icon whose name is `.custom`, which `GeneralSettings.iceIcon`'s
    /// `didSet` mirrors into `lastCustomIceIcon`.
    private var customIcon: ControlItemImageSet {
        ControlItemImageSet(name: .custom, image: .data(Data([0x01, 0x02, 0x03])))
    }

    // MARK: General settings

    @Test("Capturing General settings copies every field off the live model")
    func captureGeneralSettings() throws {
        try withScratchDefaults { _ in
            let settings = GeneralSettings()
            settings.showIceIcon = false
            settings.iceIcon = namedIcon
            // Assigned after `iceIcon` on purpose: a `.custom` icon would
            // overwrite it through `iceIcon`'s `didSet`.
            settings.lastCustomIceIcon = customIcon
            settings.customIceIconIsTemplate = true
            settings.useIceBar = true
            settings.useIceBarOnlyOnNotchedDisplay = true
            settings.iceBarLocation = .iceIcon
            settings.iceBarLocationOnHotkey = true
            settings.showOnClick = false
            settings.showOnDoubleClick = false
            settings.showOnHover = true
            settings.showOnScroll = false
            settings.autoRehide = false
            settings.rehideStrategy = .focusedApp
            settings.rehideInterval = 42

            let snapshot = GeneralSettingsSnapshot.capture(from: settings)

            #expect(snapshot.showIceIcon == false)
            #expect(snapshot.iceIcon == namedIcon)
            #expect(snapshot.lastCustomIceIcon == customIcon)
            #expect(snapshot.customIceIconIsTemplate)
            #expect(snapshot.useIceBar)
            #expect(snapshot.useIceBarOnlyOnNotchedDisplay)
            #expect(snapshot.iceBarLocation == .iceIcon)
            #expect(snapshot.iceBarLocationOnHotkey)
            #expect(snapshot.showOnClick == false)
            #expect(snapshot.showOnDoubleClick == false)
            #expect(snapshot.showOnHover)
            #expect(snapshot.showOnScroll == false)
            #expect(snapshot.autoRehide == false)
            // The snapshot stores the strategy's raw value, not the enum, so
            // an unrecognized value from a newer build can survive a profile
            // written by that build.
            #expect(snapshot.rehideStrategyRawValue == RehideStrategy.focusedApp.rawValue)
            #expect(snapshot.rehideInterval == 42)
        }
    }

    @Test("A captured General snapshot with no custom icon reports none")
    func captureGeneralSettingsWithoutACustomIcon() throws {
        try withScratchDefaults { _ in
            let settings = GeneralSettings()

            let snapshot = GeneralSettingsSnapshot.capture(from: settings)

            #expect(snapshot.lastCustomIceIcon == nil)
            #expect(snapshot.iceIcon == Defaults.DefaultValue.iceIcon)
        }
    }

    @Test("Applying a General snapshot writes every field onto the live model")
    func applyGeneralSettings() throws {
        try withScratchDefaults { _ in
            let settings = GeneralSettings()
            let snapshot = GeneralSettingsSnapshot(
                showIceIcon: false,
                iceIcon: namedIcon,
                lastCustomIceIcon: customIcon,
                customIceIconIsTemplate: true,
                useIceBar: true,
                useIceBarOnlyOnNotchedDisplay: true,
                iceBarLocation: .mousePointer,
                iceBarLocationOnHotkey: true,
                showOnClick: false,
                showOnDoubleClick: false,
                showOnHover: true,
                showOnScroll: false,
                autoRehide: false,
                rehideStrategyRawValue: RehideStrategy.timed.rawValue,
                rehideInterval: 99
            )

            snapshot.apply(to: settings)

            #expect(settings.showIceIcon == false)
            #expect(settings.iceIcon == namedIcon)
            #expect(settings.lastCustomIceIcon == customIcon)
            #expect(settings.customIceIconIsTemplate)
            #expect(settings.useIceBar)
            #expect(settings.useIceBarOnlyOnNotchedDisplay)
            #expect(settings.iceBarLocation == .mousePointer)
            #expect(settings.iceBarLocationOnHotkey)
            #expect(settings.showOnClick == false)
            #expect(settings.showOnDoubleClick == false)
            #expect(settings.showOnHover)
            #expect(settings.showOnScroll == false)
            #expect(settings.autoRehide == false)
            #expect(settings.rehideStrategy == .timed)
            #expect(settings.rehideInterval == 99)
        }
    }

    @Test("Applying a General snapshot persists the applied values through Defaults")
    func applyGeneralSettingsPersists() throws {
        try withScratchDefaults { suite in
            let settings = GeneralSettings()
            var snapshot = GeneralSettingsSnapshot.capture(from: settings)
            snapshot.showOnHover = true
            snapshot.rehideInterval = 77
            snapshot.rehideStrategyRawValue = RehideStrategy.focusedApp.rawValue

            snapshot.apply(to: settings)

            // A profile switch has to outlive the launch. The models persist
            // through `didSet`, so the scratch domain shows it.
            #expect(suite.object(forKey: Defaults.Key.showOnHover.rawValue) as? Bool == true)
            #expect(suite.object(forKey: Defaults.Key.rehideInterval.rawValue) as? Double == 77)
            #expect(
                suite.object(forKey: Defaults.Key.rehideStrategy.rawValue) as? Int
                    == RehideStrategy.focusedApp.rawValue
            )
        }
    }

    /// The raw value is stored so a profile from a newer build survives an
    /// older one, which keeps the strategy already in effect instead of
    /// resetting.
    @Test("An unrecognized rehide strategy leaves the live strategy standing")
    func applyGeneralSettingsWithUnknownRehideStrategy() throws {
        try withScratchDefaults { _ in
            let settings = GeneralSettings()
            settings.rehideStrategy = .focusedApp
            var snapshot = GeneralSettingsSnapshot.capture(from: settings)
            // No `RehideStrategy` case has this raw value.
            snapshot.rehideStrategyRawValue = 9999
            snapshot.rehideInterval = 33

            snapshot.apply(to: settings)

            #expect(settings.rehideStrategy == .focusedApp)
            // The rest of the snapshot still lands: a single unknown value
            // must not abandon the remainder of the restore.
            #expect(settings.rehideInterval == 33)
        }
    }

    /// `iceIcon`'s `didSet` mirrors a `.custom` icon into `lastCustomIceIcon`,
    /// so `apply(to:)` assigns `lastCustomIceIcon` last to keep the custom icon
    /// the profile remembered.
    @Test("Applying a custom Ice icon keeps the snapshot's last-custom icon")
    func applyGeneralSettingsCustomIconKeepsLastCustom() throws {
        try withScratchDefaults { _ in
            let settings = GeneralSettings()
            let snapshot = GeneralSettingsSnapshot(
                showIceIcon: true,
                iceIcon: customIcon,
                lastCustomIceIcon: ControlItemImageSet(name: .custom, image: .data(Data([0xFF]))),
                customIceIconIsTemplate: false,
                useIceBar: false,
                useIceBarOnlyOnNotchedDisplay: false,
                iceBarLocation: .dynamic,
                iceBarLocationOnHotkey: false,
                showOnClick: true,
                showOnDoubleClick: true,
                showOnHover: false,
                showOnScroll: true,
                autoRehide: true,
                rehideStrategyRawValue: RehideStrategy.smart.rawValue,
                rehideInterval: 15
            )

            snapshot.apply(to: settings)

            #expect(settings.iceIcon == customIcon)
            #expect(settings.lastCustomIceIcon == snapshot.lastCustomIceIcon)
            #expect(settings.lastCustomIceIcon != customIcon)
        }
    }

    // MARK: Advanced settings

    @Test("Capturing Advanced settings copies every field off the live model")
    func captureAdvancedSettings() throws {
        try withScratchDefaults { _ in
            let settings = AdvancedSettings()
            settings.enableAlwaysHiddenSection = true
            settings.showAllSectionsOnUserDrag = false
            settings.sectionDividerStyle = .chevron
            settings.hideApplicationMenus = false
            settings.enableSecondaryContextMenu = false
            settings.enableSecondaryContextMenuQuit = true
            settings.showOnHoverDelay = 0.75
            settings.tooltipDelay = 1.25
            settings.showMenuBarTooltips = true
            settings.iconRefreshInterval = 2.5
            settings.useDoubleClickToShowAlwaysHiddenSection = true
            settings.useOptionClickToShowAlwaysHiddenSection = true
            settings.enableMenuBarItemOverflow = false
            settings.useThawBarOnNotchOverflow = false
            settings.searchSectionOrder = [.alwaysHidden, .visible, .hidden]
            settings.searchIncludeVisible = false
            settings.searchIncludeHidden = false
            settings.searchIncludeAlwaysHidden = false
            settings.moveCursorToRevealedItem = true

            let snapshot = AdvancedSettingsSnapshot.capture(from: settings)

            #expect(snapshot.enableAlwaysHiddenSection)
            #expect(snapshot.showAllSectionsOnUserDrag == false)
            #expect(snapshot.sectionDividerStyle == SectionDividerStyle.chevron.rawValue)
            #expect(snapshot.hideApplicationMenus == false)
            #expect(snapshot.enableSecondaryContextMenu == false)
            #expect(snapshot.enableSecondaryContextMenuQuit)
            #expect(snapshot.showOnHoverDelay == 0.75)
            #expect(snapshot.tooltipDelay == 1.25)
            #expect(snapshot.showMenuBarTooltips)
            #expect(snapshot.iconRefreshInterval == 1.0)
            #expect(snapshot.useDoubleClickToShowAlwaysHiddenSection)
            #expect(snapshot.useOptionClickToShowAlwaysHiddenSection)
            #expect(snapshot.enableMenuBarItemOverflow == false)
            #expect(snapshot.useThawBarOnNotchOverflow == false)
            // The snapshot stores raw strings so a section name this build does
            // not know still survives the profile.
            #expect(snapshot.searchSectionOrder == ["alwaysHidden", "visible", "hidden"])
            #expect(snapshot.searchIncludeVisible == false)
            #expect(snapshot.searchIncludeHidden == false)
            #expect(snapshot.searchIncludeAlwaysHidden == false)
            #expect(snapshot.moveCursorToRevealedItem)
            // Left at the compiled-in default; see the suite's deliberate gaps.
        }
    }

    @Test("Applying an Advanced snapshot writes every field onto the live model")
    func applyAdvancedSettings() throws {
        try withScratchDefaults { _ in
            let settings = AdvancedSettings()
            let snapshot = AdvancedSettingsSnapshot(
                enableAlwaysHiddenSection: true,
                showAllSectionsOnUserDrag: false,
                sectionDividerStyle: SectionDividerStyle.chevron.rawValue,
                hideApplicationMenus: false,
                enableSecondaryContextMenu: false,
                enableSecondaryContextMenuQuit: true,
                showOnHoverDelay: 0.75,
                tooltipDelay: 1.25,
                showMenuBarTooltips: true,
                iconRefreshInterval: 2.5,
                useDoubleClickToShowAlwaysHiddenSection: true,
                useOptionClickToShowAlwaysHiddenSection: true,
                enableMenuBarItemOverflow: false,
                useThawBarOnNotchOverflow: false,
                searchSectionOrder: ["alwaysHidden", "hidden", "visible"],
                searchIncludeVisible: false,
                searchIncludeHidden: false,
                searchIncludeAlwaysHidden: false,
                moveCursorToRevealedItem: true
            )

            snapshot.apply(to: settings)

            #expect(settings.enableAlwaysHiddenSection)
            #expect(settings.showAllSectionsOnUserDrag == false)
            #expect(settings.sectionDividerStyle == .chevron)
            #expect(settings.hideApplicationMenus == false)
            #expect(settings.enableSecondaryContextMenu == false)
            #expect(settings.enableSecondaryContextMenuQuit)
            #expect(settings.showOnHoverDelay == 0.75)
            #expect(settings.tooltipDelay == 1.25)
            #expect(settings.showMenuBarTooltips)
            #expect(settings.iconRefreshInterval == 1.0)
            #expect(Defaults.double(forKey: .iconRefreshInterval) == 1.0)
            #expect(settings.useDoubleClickToShowAlwaysHiddenSection)
            #expect(settings.useOptionClickToShowAlwaysHiddenSection)
            #expect(settings.enableMenuBarItemOverflow == false)
            #expect(settings.useThawBarOnNotchOverflow == false)
            #expect(settings.searchSectionOrder == [.alwaysHidden, .hidden, .visible])
            #expect(settings.searchIncludeVisible == false)
            #expect(settings.searchIncludeHidden == false)
            #expect(settings.searchIncludeAlwaysHidden == false)
            #expect(settings.moveCursorToRevealedItem)
        }
    }

    /// A profile written by an older build lists fewer sections than this build
    /// knows, and one written by a newer build can list a name this build does
    /// not. `apply(to:)` runs the raw list through
    /// `AdvancedSettings.sanitizedSearchSectionOrder(from:)` so the search panel
    /// still ends up with every section exactly once.
    @Test("A short or unknown search section order is completed on apply")
    func applyAdvancedSettingsSanitizesTheSearchSectionOrder() throws {
        try withScratchDefaults { _ in
            let settings = AdvancedSettings()
            var snapshot = AdvancedSettingsSnapshot.capture(from: settings)
            snapshot.searchSectionOrder = ["hidden", "somethingThisBuildDoesNotKnow"]

            snapshot.apply(to: settings)

            #expect(settings.searchSectionOrder.first == .hidden)
            #expect(Set(settings.searchSectionOrder) == Set(MenuBarSection.Name.allCases))
            #expect(settings.searchSectionOrder.count == MenuBarSection.Name.allCases.count)
        }
    }

    /// Same forward-compatibility contract as the rehide strategy: the divider
    /// style is stored as an `Int`, so a value from a newer build has to leave
    /// the current style alone rather than reset it.
    @Test("An unrecognized section divider style leaves the live style standing")
    func applyAdvancedSettingsWithUnknownDividerStyle() throws {
        try withScratchDefaults { _ in
            let settings = AdvancedSettings()
            settings.sectionDividerStyle = .chevron
            var snapshot = AdvancedSettingsSnapshot.capture(from: settings)
            // No `SectionDividerStyle` case has this raw value.
            snapshot.sectionDividerStyle = 9999
            snapshot.tooltipDelay = 3

            snapshot.apply(to: settings)

            #expect(settings.sectionDividerStyle == .chevron)
            // The rest of the snapshot still lands.
            #expect(settings.tooltipDelay == 3)
        }
    }

    @Test("Applying an Advanced snapshot persists the applied values through Defaults")
    func applyAdvancedSettingsPersists() throws {
        try withScratchDefaults { suite in
            let settings = AdvancedSettings()
            var snapshot = AdvancedSettingsSnapshot.capture(from: settings)
            snapshot.sectionDividerStyle = SectionDividerStyle.chevron.rawValue
            snapshot.tooltipDelay = 4.5
            snapshot.searchSectionOrder = ["alwaysHidden", "hidden", "visible"]

            snapshot.apply(to: settings)

            #expect(
                suite.object(forKey: Defaults.Key.sectionDividerStyle.rawValue) as? Int
                    == SectionDividerStyle.chevron.rawValue
            )
            #expect(suite.object(forKey: Defaults.Key.tooltipDelay.rawValue) as? Double == 4.5)
            #expect(
                suite.object(forKey: Defaults.Key.searchSectionOrder.rawValue) as? [String]
                    == ["alwaysHidden", "hidden", "visible"]
            )
        }
    }

    // MARK: Full round trip

    /// The shape a real profile save/restore takes: capture off one model,
    /// serialize, deserialize, apply to a second model. Anything `capture`
    /// forgets or `apply` skips shows up as a divergence between the two
    /// models, which no hand-built-snapshot test can see.
    @Test("A profile round trip carries the settings from one live model to another")
    func captureEncodeDecodeApplyRoundTrip() throws {
        try withScratchDefaults { _ in
            let source = GeneralSettings()
            source.showIceIcon = false
            source.iceIcon = namedIcon
            source.customIceIconIsTemplate = true
            source.useIceBar = true
            source.useIceBarOnlyOnNotchedDisplay = true
            source.iceBarLocation = .iceIcon
            source.iceBarLocationOnHotkey = true
            source.showOnClick = false
            source.showOnDoubleClick = false
            source.showOnHover = true
            source.showOnScroll = false
            source.autoRehide = false
            source.rehideStrategy = .timed
            source.rehideInterval = 55

            let data = try JSONEncoder().encode(GeneralSettingsSnapshot.capture(from: source))
            let decoded = try JSONDecoder().decode(GeneralSettingsSnapshot.self, from: data)
            let destination = GeneralSettings()
            decoded.apply(to: destination)

            #expect(destination.showIceIcon == source.showIceIcon)
            #expect(destination.iceIcon == source.iceIcon)
            #expect(destination.customIceIconIsTemplate == source.customIceIconIsTemplate)
            #expect(destination.useIceBar == source.useIceBar)
            #expect(destination.useIceBarOnlyOnNotchedDisplay == source.useIceBarOnlyOnNotchedDisplay)
            #expect(destination.iceBarLocation == source.iceBarLocation)
            #expect(destination.iceBarLocationOnHotkey == source.iceBarLocationOnHotkey)
            #expect(destination.showOnClick == source.showOnClick)
            #expect(destination.showOnDoubleClick == source.showOnDoubleClick)
            #expect(destination.showOnHover == source.showOnHover)
            #expect(destination.showOnScroll == source.showOnScroll)
            #expect(destination.autoRehide == source.autoRehide)
            #expect(destination.rehideStrategy == source.rehideStrategy)
            #expect(destination.rehideInterval == source.rehideInterval)
        }
    }

    @Test("An Advanced profile round trip carries the settings from one live model to another")
    func captureEncodeDecodeApplyAdvancedRoundTrip() throws {
        try withScratchDefaults { _ in
            let source = AdvancedSettings()
            source.enableAlwaysHiddenSection = true
            source.showAllSectionsOnUserDrag = false
            source.sectionDividerStyle = .chevron
            source.hideApplicationMenus = false
            source.enableSecondaryContextMenu = false
            source.enableSecondaryContextMenuQuit = true
            source.showOnHoverDelay = 0.6
            source.tooltipDelay = 0.9
            source.showMenuBarTooltips = true
            source.iconRefreshInterval = 1.5
            source.useDoubleClickToShowAlwaysHiddenSection = true
            source.useOptionClickToShowAlwaysHiddenSection = true
            source.enableMenuBarItemOverflow = false
            source.useThawBarOnNotchOverflow = false
            source.searchSectionOrder = [.hidden, .alwaysHidden, .visible]
            source.searchIncludeVisible = false
            source.searchIncludeHidden = false
            source.searchIncludeAlwaysHidden = false

            let data = try JSONEncoder().encode(AdvancedSettingsSnapshot.capture(from: source))
            let decoded = try JSONDecoder().decode(AdvancedSettingsSnapshot.self, from: data)
            let destination = AdvancedSettings()
            decoded.apply(to: destination)

            #expect(destination.enableAlwaysHiddenSection == source.enableAlwaysHiddenSection)
            #expect(destination.showAllSectionsOnUserDrag == source.showAllSectionsOnUserDrag)
            #expect(destination.sectionDividerStyle == source.sectionDividerStyle)
            #expect(destination.hideApplicationMenus == source.hideApplicationMenus)
            #expect(destination.enableSecondaryContextMenu == source.enableSecondaryContextMenu)
            #expect(destination.enableSecondaryContextMenuQuit == source.enableSecondaryContextMenuQuit)
            #expect(destination.showOnHoverDelay == source.showOnHoverDelay)
            #expect(destination.tooltipDelay == source.tooltipDelay)
            #expect(destination.showMenuBarTooltips == source.showMenuBarTooltips)
            #expect(destination.iconRefreshInterval == source.iconRefreshInterval)
            #expect(
                destination.useDoubleClickToShowAlwaysHiddenSection
                    == source.useDoubleClickToShowAlwaysHiddenSection
            )
            #expect(
                destination.useOptionClickToShowAlwaysHiddenSection
                    == source.useOptionClickToShowAlwaysHiddenSection
            )
            #expect(destination.enableMenuBarItemOverflow == source.enableMenuBarItemOverflow)
            #expect(destination.useThawBarOnNotchOverflow == source.useThawBarOnNotchOverflow)
            #expect(destination.searchSectionOrder == source.searchSectionOrder)
            #expect(destination.searchIncludeVisible == source.searchIncludeVisible)
            #expect(destination.searchIncludeHidden == source.searchIncludeHidden)
            #expect(destination.searchIncludeAlwaysHidden == source.searchIncludeAlwaysHidden)
        }
    }
}

// MARK: - Layout resolution

/// Covers `MenuBarLayoutSnapshot`'s two resolution accessors, which keep
/// profiles written before `itemOrder` and `itemSectionMap` applying the same
/// layout. `ProfileTests` covers the plain legacy fallback; this covers the
/// precedence between the two and what happens when they disagree.
@Suite("Menu bar layout snapshot resolution")
struct MenuBarLayoutSnapshotResolutionTests {
    private func makeSnapshot(
        savedSectionOrder: [String: [String]] = [:],
        itemSectionMap: [String: String]? = nil,
        itemOrder: [String: [String]]? = nil
    ) -> MenuBarLayoutSnapshot {
        MenuBarLayoutSnapshot(
            savedSectionOrder: savedSectionOrder,
            pinnedHiddenBundleIDs: [],
            pinnedAlwaysHiddenBundleIDs: [],
            customNames: [:],
            itemSectionMap: itemSectionMap,
            itemOrder: itemOrder
        )
    }

    @Test("An explicit item order takes precedence over the legacy saved order")
    func itemOrderWinsOverSavedSectionOrder() {
        let snapshot = makeSnapshot(
            savedSectionOrder: ["visible": ["com.example.Legacy:Legacy"]],
            itemOrder: ["hidden": ["com.example.Current:Current"]]
        )

        #expect(snapshot.resolvedItemOrder == ["hidden": ["com.example.Current:Current"]])
    }

    @Test("An explicit section map takes precedence over the ordered representation")
    func itemSectionMapWinsOverOrder() {
        // The two disagree on purpose: `itemSectionMap` is the source of truth
        // for apps like Control Center that share one bundle ID across many
        // items, so the ordered representation must not override it.
        let snapshot = makeSnapshot(
            itemSectionMap: ["com.apple.controlcenter:WiFi": "alwaysHidden"],
            itemOrder: ["visible": ["com.apple.controlcenter:WiFi"]]
        )

        #expect(snapshot.resolvedItemSectionMap == ["com.apple.controlcenter:WiFi": "alwaysHidden"])
    }

    @Test("With no explicit map, each identifier takes the section that lists it")
    func sectionMapIsInvertedFromItemOrder() {
        let snapshot = makeSnapshot(
            itemOrder: [
                "visible": ["a:A", "b:B"],
                "hidden": ["c:C"],
                "alwaysHidden": ["d:D"],
            ]
        )

        #expect(snapshot.resolvedItemSectionMap == [
            "a:A": "visible",
            "b:B": "visible",
            "c:C": "hidden",
            "d:D": "alwaysHidden",
        ])
    }

    @Test("With neither representation populated the resolved map is empty")
    func emptyLayoutResolvesToAnEmptyMap() {
        let snapshot = makeSnapshot()

        #expect(snapshot.resolvedItemOrder.isEmpty)
        #expect(snapshot.resolvedItemSectionMap.isEmpty)
    }

    /// One identifier under two sections has no stable answer: the inversion
    /// walks a `Dictionary` whose order varies with the hash seed, so the
    /// strongest claim is that it lands in one of the two.
    @Test("An identifier listed twice resolves to one of its sections, unpredictably")
    func duplicateIdentifierResolvesToOneSection() {
        let snapshot = makeSnapshot(
            itemOrder: [
                "visible": ["duplicate:Item"],
                "hidden": ["duplicate:Item"],
            ]
        )

        let resolved = snapshot.resolvedItemSectionMap
        #expect(resolved.count == 1)
        #expect(resolved["duplicate:Item"] == "visible" || resolved["duplicate:Item"] == "hidden")
    }
}

// MARK: - Decoding asymmetry

/// Pins the strict side of partial decoding: `GeneralSettingsSnapshot` uses the
/// synthesized `init(from:)` and requires every key, while
/// `AdvancedSettingsSnapshot` fills missing keys from `Defaults.DefaultValue`.
/// The asymmetry decides whether a hand-edited or truncated profile loads.
@Suite("Profile decoding of partial settings objects")
struct ProfilePartialSettingsDecodingTests {
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test("A profile whose General settings object is incomplete fails to decode")
    func partialGeneralSettingsObjectThrows() {
        // Present but missing every key except one. `decodeIfPresent` only
        // returns nil for an absent or null value, so this reaches the
        // synthesized initializer, which has no per-field fallback.
        let json = Data(#"{"name":"Partial","generalSettings":{"showIceIcon":true}}"#.utf8)

        #expect(throws: DecodingError.self) {
            try decoder.decode(Profile.self, from: json)
        }
    }

    @Test("A profile whose Advanced settings object is incomplete decodes with defaults")
    func partialAdvancedSettingsObjectFallsBackToDefaults() throws {
        let json = Data(#"{"name":"Partial","advancedSettings":{"tooltipDelay":9}}"#.utf8)

        let profile = try decoder.decode(Profile.self, from: json)

        #expect(profile.advancedSettings.tooltipDelay == 9)
        #expect(profile.advancedSettings.showOnHoverDelay == Defaults.DefaultValue.showOnHoverDelay)
        #expect(
            profile.advancedSettings.sectionDividerStyle
                == Defaults.DefaultValue.sectionDividerStyle.rawValue
        )
        #expect(profile.advancedSettings.searchSectionOrder == Defaults.DefaultValue.searchSectionOrder)
    }

    @Test("A null General settings value falls back to the shipped defaults")
    func nullGeneralSettingsFallsBackToDefaults() throws {
        // `null` is the one shape `decodeIfPresent` treats as absent, so this
        // takes the fallback branch rather than the throwing one above.
        let json = Data(#"{"name":"Nulled","generalSettings":null}"#.utf8)

        let profile = try decoder.decode(Profile.self, from: json)

        #expect(profile.generalSettings.showIceIcon == Defaults.DefaultValue.showIceIcon)
        #expect(profile.generalSettings.iceIcon == Defaults.DefaultValue.iceIcon)
        #expect(profile.generalSettings.lastCustomIceIcon == nil)
        #expect(
            profile.generalSettings.rehideStrategyRawValue
                == Defaults.DefaultValue.rehideStrategy.rawValue
        )
    }
}

// MARK: - Regressions

/// Pins two bugs where a profile silently lost information it had stored.
@MainActor
@Suite("Profile snapshot regressions", .serialized)
struct ProfileSnapshotRegressionTests {
    /// `captureCurrentLayout` writes `[:]`, not `nil`, while the menu bar is
    /// still settling, so a plain `itemOrder ?? savedSectionOrder` handed the
    /// apply path an empty layout next to a good `savedSectionOrder`.
    @Test("An empty item order falls back to the saved section order")
    func emptyItemOrderFallsBackToSavedSectionOrder() {
        let saved = ["visible": ["com.example.A"], "hidden": ["com.example.B"]]
        let layout = MenuBarLayoutSnapshot(
            savedSectionOrder: saved,
            pinnedHiddenBundleIDs: [],
            pinnedAlwaysHiddenBundleIDs: [],
            customNames: [:],
            itemOrder: [:]
        )

        #expect(layout.resolvedItemOrder == saved)
        #expect(layout.resolvedItemSectionMap["com.example.A"] == "visible")
        #expect(layout.resolvedItemSectionMap["com.example.B"] == "hidden")
    }

    /// A populated `itemOrder` must still win, or the fallback would override
    /// every layout written by a current build.
    @Test("A populated item order still takes precedence")
    func populatedItemOrderStillWins() {
        let layout = MenuBarLayoutSnapshot(
            savedSectionOrder: ["visible": ["com.example.Legacy"]],
            pinnedHiddenBundleIDs: [],
            pinnedAlwaysHiddenBundleIDs: [],
            customNames: [:],
            itemOrder: ["hidden": ["com.example.Current"]]
        )

        #expect(layout.resolvedItemOrder == ["hidden": ["com.example.Current"]])
    }

    /// With both empty there is nothing to prefer, and the result must stay
    /// empty rather than becoming nil-shaped in some other way.
    @Test("Both empty resolves to empty")
    func bothEmptyResolvesToEmpty() {
        let layout = MenuBarLayoutSnapshot(
            savedSectionOrder: [:],
            pinnedHiddenBundleIDs: [],
            pinnedAlwaysHiddenBundleIDs: [],
            customNames: [:],
            itemOrder: [:]
        )

        #expect(layout.resolvedItemOrder.isEmpty)
        #expect(layout.resolvedItemSectionMap.isEmpty)
    }

    /// `iceIcon`'s `didSet` mirrors a `.custom` icon into `lastCustomIceIcon`,
    /// so assigning `lastCustomIceIcon` first let the mirror overwrite the
    /// custom icon the profile remembered.
    @Test("Applying a snapshot keeps its own lastCustomIceIcon")
    func applyPreservesLastCustomIceIcon() throws {
        try withScratchDefaults { _ in
            let settings = GeneralSettings()
            let remembered = ControlItemImageSet.defaultIceIcon
            var snapshot = GeneralSettingsSnapshot.capture(from: settings)
            snapshot.lastCustomIceIcon = remembered

            snapshot.apply(to: settings)

            #expect(settings.lastCustomIceIcon == remembered)
        }
    }
}
