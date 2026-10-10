//
//  IceSettingsImporterTailTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers the parts of ``IceSettingsImporter`` that ``IceSettingsImporterTests``
/// leaves alone: the general, advanced and hotkey mappings, the per-display
/// gate, and the V2 appearance path.
///
/// Ice's domain was written by another, possibly much older binary and is
/// copied unvalidated, so absent keys, wrong types and empty containers are
/// the cases that matter.
///
/// Every case runs inside `withScratchDefaults` in a `.serialized` suite,
/// against a throwaway Ice `UserDefaults` suite per test.
///
/// Gaps:
/// - The `UseIceBar == true` branch of `importPerDisplayIceBarSettings` walks
///   `NSScreen.screens` through `DisplayIceBarConfiguration.buildConfigurations`,
///   so its result depends on the attached displays. Only the "no Thaw Bar to
///   convert" side is covered.
/// - `importPerDisplayIceBarSettings`' `diagLog.error` arm is unreachable:
///   `JSONEncoder` cannot fail on `[String: DisplayIceBarConfiguration]`.
@MainActor
@Suite("Ice settings importer tail", .serialized)
struct IceSettingsImporterTailTests {
    /// A V2 appearance blob that is distinguishable from the default, so a test
    /// can tell "the importer wrote this one" from "the importer wrote
    /// something".
    private var markedV2Configuration: MenuBarAppearanceConfigurationV2 {
        var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        configuration.shapeKind = .full
        configuration.leftMargin = 7
        configuration.isDynamic = true
        return configuration
    }

    /// Whether `key` is absent from the store the importer wrote to.
    ///
    /// Spelled out rather than inlined into `#expect` because
    /// `UserDefaults.object(forKey:)` returns `Any?`, which the expectation
    /// macro cannot compare against `nil` directly.
    private func absent(_ key: Defaults.Key, from suite: UserDefaults) -> Bool {
        suite.object(forKey: key.rawValue) == nil
    }

    /// Opens a throwaway defaults suite seeded with `values`, standing in for
    /// Ice's own domain.
    ///
    /// The suite sees its own keys plus the global domain, nothing this build
    /// writes. Thaw's `Defaults.Key` raw values are the strings the importer
    /// looks up in Ice's domain, so a leak would show up as phantom imports.
    private func makeSource(_ values: [String: Any]) throws -> (defaults: UserDefaults, domainName: String) {
        let domainName = "com.stonerl.ThawTests.IceSettingsImporterTail.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domainName))
        for (key, value) in values {
            defaults.set(value, forKey: key)
        }
        return (defaults, domainName)
    }

    // MARK: Unavailable source

    @Test("A missing Ice defaults domain reports no settings and imports nothing")
    func missingIceDefaultsImportsNothing() throws {
        try withScratchDefaults { _ in
            let importer = IceSettingsImporter(
                iceUserDefaults: nil,
                iceDomainName: "com.jordanbaird.Ice",
                saveAppearanceConfiguration: { _ in
                    Issue.record("nothing may be written when Ice's defaults are unreachable")
                }
            )

            #expect(!importer.hasIceSettings())
            let result = importer.importIceSettings()

            // `false` is the signal the onboarding flow uses to keep the
            // "import from Ice" offer hidden, so it has to be distinct from
            // "Ice is installed but has nothing worth importing".
            #expect(!result.success)
            #expect(result.settingsImported == 0)
        }
    }

    @Test("An empty Ice domain reports no settings but still imports successfully")
    func emptyIceDomainImportsNothing() throws {
        try withScratchDefaults { _ in
            let (source, domainName) = try makeSource([:])
            defer { source.removePersistentDomain(forName: domainName) }

            let importer = IceSettingsImporter(
                iceUserDefaults: source,
                iceDomainName: domainName,
                saveAppearanceConfiguration: { _ in
                    Issue.record("nothing may be written for an empty Ice domain")
                }
            )

            #expect(!importer.hasIceSettings())
            let result = importer.importIceSettings()

            #expect(result.success)
            #expect(result.settingsImported == 0)
        }
    }

    // MARK: Full sweep

    /// One pass over every mapping the importer knows, so the per-key loops and
    /// the sum in `importIceSettings` are all driven together. `UseIceBar` is
    /// deliberately `false`: see the suite's gaps.
    @Test("A fully populated Ice domain imports every mapped key exactly once")
    func fullyPopulatedDomainImportsEveryMapping() throws {
        try withScratchDefaults { suite in
            let iconData = try JSONEncoder().encode(
                ControlItemImageSet(name: .door, image: .symbol("door.left.hand.closed"))
            )
            let appearanceData = try JSONEncoder().encode(markedV2Configuration)
            let (source, domainName) = try makeSource([
                // General: 11 mappings.
                "ShowIceIcon": false,
                "IceIcon": iconData,
                "CustomIceIconIsTemplate": true,
                "UseIceBar": false,
                "IceBarLocation": 2,
                "ShowOnClick": false,
                "ShowOnHover": true,
                "ShowOnScroll": false,
                "AutoRehide": false,
                "RehideStrategy": 1,
                "RehideInterval": 42.0,
                // Advanced: 6 mappings.
                "EnableAlwaysHiddenSection": true,
                "ShowAllSectionsOnUserDrag": false,
                "SectionDividerStyle": 1,
                "HideApplicationMenus": false,
                "EnableSecondaryContextMenu": false,
                "ShowOnHoverDelay": 0.75,
                // Hotkeys: 2.
                "Hotkeys": ["toggle": Data([0x01, 0x02]), "search": Data([0x03])],
                // Appearance: 1.
                "MenuBarAppearanceConfigurationV2": appearanceData,
            ])
            defer { source.removePersistentDomain(forName: domainName) }

            var writes = [Data]()
            let importer = IceSettingsImporter(
                iceUserDefaults: source,
                iceDomainName: domainName,
                saveAppearanceConfiguration: { writes.append($0) }
            )

            #expect(importer.hasIceSettings())
            let result = importer.importIceSettings()

            #expect(result.success)
            // 11 general + 0 per-display + 6 advanced + 2 hotkeys + 1 appearance.
            #expect(result.settingsImported == 20)

            // Booleans are read back through `object(forKey:)` rather than
            // `bool(forKey:)` so that "imported as false" is distinguishable
            // from "never written".
            #expect(suite.object(forKey: Defaults.Key.showIceIcon.rawValue) as? Bool == false)
            #expect(suite.object(forKey: Defaults.Key.customIceIconIsTemplate.rawValue) as? Bool == true)
            #expect(suite.object(forKey: Defaults.Key.iceIcon.rawValue) as? Data == iconData)
            #expect(suite.object(forKey: Defaults.Key.iceBarLocation.rawValue) as? Int == 2)
            #expect(suite.object(forKey: Defaults.Key.rehideStrategy.rawValue) as? Int == 1)
            #expect(suite.object(forKey: Defaults.Key.rehideInterval.rawValue) as? Double == 42)
            #expect(suite.object(forKey: Defaults.Key.enableAlwaysHiddenSection.rawValue) as? Bool == true)
            #expect(suite.object(forKey: Defaults.Key.sectionDividerStyle.rawValue) as? Int == 1)
            #expect(suite.object(forKey: Defaults.Key.showOnHoverDelay.rawValue) as? Double == 0.75)

            let hotkeys = try #require(suite.dictionary(forKey: Defaults.Key.hotkeys.rawValue))
            #expect(hotkeys.compactMapValues { $0 as? Data } == [
                "toggle": Data([0x01, 0x02]),
                "search": Data([0x03]),
            ])

            #expect(writes == [appearanceData])
        }
    }

    // MARK: Absent and mistyped keys

    @Test("Keys Ice never wrote are left absent rather than defaulted")
    func absentKeysAreNotWritten() throws {
        try withScratchDefaults { suite in
            let (source, domainName) = try makeSource(["ShowIceIcon": false])
            defer { source.removePersistentDomain(forName: domainName) }

            let importer = IceSettingsImporter(
                iceUserDefaults: source,
                iceDomainName: domainName,
                saveAppearanceConfiguration: { _ in
                    Issue.record("no appearance data was offered")
                }
            )

            let result = importer.importIceSettings()

            #expect(result.settingsImported == 1)
            // Writing a compiled-in default for a key Ice never set would look
            // to the rest of the app like a deliberate user choice.
            #expect(absent(.rehideInterval, from: suite))
            #expect(absent(.autoRehide, from: suite))
            #expect(absent(.enableAlwaysHiddenSection, from: suite))
            #expect(absent(.hotkeys, from: suite))
        }
    }

    /// The mapping loop copies whatever object it finds without checking its
    /// type, so a key Ice stored as a string lands in Thaw's domain as a string
    /// under a key the app reads as a `Bool`. Pinned as observed behaviour, not
    /// endorsed.
    @Test("A mistyped Ice value is copied verbatim and still counted as imported")
    func mistypedValuesAreCopiedVerbatim() throws {
        try withScratchDefaults { suite in
            let (source, domainName) = try makeSource(["UseIceBar": "yes", "ShowOnHover": 3])
            defer { source.removePersistentDomain(forName: domainName) }

            let importer = IceSettingsImporter(
                iceUserDefaults: source,
                iceDomainName: domainName,
                saveAppearanceConfiguration: { _ in
                    Issue.record("no appearance data was offered")
                }
            )

            let result = importer.importIceSettings()

            #expect(result.settingsImported == 2)
            #expect(suite.object(forKey: Defaults.Key.useIceBar.rawValue) as? String == "yes")
            #expect(suite.object(forKey: Defaults.Key.showOnHover.rawValue) as? Int == 3)
        }
    }

    @Test("A Thaw Bar that Ice had switched off generates no per-display configuration")
    func disabledIceBarGeneratesNoPerDisplayConfiguration() throws {
        try withScratchDefaults { suite in
            let (source, domainName) = try makeSource([
                "UseIceBar": false,
                "IceBarLocation": 1,
                "UseIceBarOnlyOnNotchedDisplay": true,
            ])
            defer { source.removePersistentDomain(forName: domainName) }

            let importer = IceSettingsImporter(
                iceUserDefaults: source,
                iceDomainName: domainName,
                saveAppearanceConfiguration: { _ in
                    Issue.record("no appearance data was offered")
                }
            )

            let result = importer.importIceSettings()

            // `UseIceBar` and `IceBarLocation` are in the general mapping;
            // `UseIceBarOnlyOnNotchedDisplay` is not, and only feeds the
            // per-display conversion, which this domain does not trigger.
            #expect(result.settingsImported == 2)
            #expect(absent(.displayIceBarConfigurations, from: suite))
            #expect(absent(.hasMigratedPerDisplayIceBar, from: suite))
        }
    }

    // No test covers `UseIceBar` stored as the integer 1: `bool(forKey:)` reads
    // it as `true`, and the per-display conversion then depends on how many
    // displays are attached.

    // MARK: Hotkeys

    @Test("Ice hotkeys stored as one opaque blob are imported through the fallback")
    func hotkeysStoredAsASingleBlobAreImported() throws {
        try withScratchDefaults { suite in
            let blob = Data([0xDE, 0xAD, 0xBE, 0xEF])
            let (source, domainName) = try makeSource(["Hotkeys": blob])
            defer { source.removePersistentDomain(forName: domainName) }

            let importer = IceSettingsImporter(
                iceUserDefaults: source,
                iceDomainName: domainName,
                saveAppearanceConfiguration: { _ in
                    Issue.record("no appearance data was offered")
                }
            )

            let result = importer.importIceSettings()

            // A blob counts as one setting however many bindings it holds,
            // because the importer does not decode it.
            #expect(result.settingsImported == 1)
            #expect(suite.object(forKey: Defaults.Key.hotkeys.rawValue) as? Data == blob)
        }
    }

    @Test("A hotkeys dictionary holding no data values imports nothing")
    func hotkeysDictionaryWithoutDataValuesImportsNothing() throws {
        try withScratchDefaults { suite in
            let (source, domainName) = try makeSource([
                "Hotkeys": ["toggle": "not-a-key-combination", "search": 42],
            ])
            defer { source.removePersistentDomain(forName: domainName) }

            let importer = IceSettingsImporter(
                iceUserDefaults: source,
                iceDomainName: domainName,
                saveAppearanceConfiguration: { _ in
                    Issue.record("no appearance data was offered")
                }
            )

            let result = importer.importIceSettings()

            // Writing an empty dictionary would clear whatever hotkeys Thaw
            // already has, which is worse than importing nothing.
            #expect(result.settingsImported == 0)
            #expect(absent(.hotkeys, from: suite))
        }
    }

    @Test("A hotkeys dictionary is imported down to only its data values")
    func hotkeysDictionaryIsFilteredToDataValues() throws {
        try withScratchDefaults { suite in
            let (source, domainName) = try makeSource([
                "Hotkeys": ["toggle": Data([0x01]), "junk": "not-a-key-combination"],
            ])
            defer { source.removePersistentDomain(forName: domainName) }

            let importer = IceSettingsImporter(
                iceUserDefaults: source,
                iceDomainName: domainName,
                saveAppearanceConfiguration: { _ in
                    Issue.record("no appearance data was offered")
                }
            )

            let result = importer.importIceSettings()

            #expect(result.settingsImported == 1)
            let hotkeys = try #require(suite.dictionary(forKey: Defaults.Key.hotkeys.rawValue))
            #expect(hotkeys.compactMapValues { $0 as? Data } == ["toggle": Data([0x01])])
            #expect(hotkeys.count == 1)
        }
    }

    // MARK: Appearance

    @Test("A V2 appearance configuration is handed over byte for byte")
    func v2AppearanceIsPassedThroughUnchanged() throws {
        try withScratchDefaults { _ in
            let appearanceData = try JSONEncoder().encode(markedV2Configuration)
            let (source, domainName) = try makeSource([
                "MenuBarAppearanceConfigurationV2": appearanceData,
            ])
            defer { source.removePersistentDomain(forName: domainName) }

            var writes = [Data]()
            let importer = IceSettingsImporter(
                iceUserDefaults: source,
                iceDomainName: domainName,
                saveAppearanceConfiguration: { writes.append($0) }
            )

            let result = importer.importIceSettings()

            #expect(result.settingsImported == 1)
            #expect(writes.count == 1)
            // Ice's V2 format is Thaw's V2 format, so the importer must not
            // re-encode it: a round trip through this build's model would drop
            // any field Ice wrote that this build does not know.
            #expect(writes.first == appearanceData)
        }
    }

    @Test("A V2 appearance value that is not data is ignored")
    func mistypedV2AppearanceIsIgnored() throws {
        try withScratchDefaults { _ in
            let (source, domainName) = try makeSource([
                "MenuBarAppearanceConfigurationV2": "not-data",
            ])
            defer { source.removePersistentDomain(forName: domainName) }

            let importer = IceSettingsImporter(
                iceUserDefaults: source,
                iceDomainName: domainName,
                saveAppearanceConfiguration: { _ in
                    Issue.record("a non-data appearance value must not be written")
                }
            )

            let result = importer.importIceSettings()

            #expect(result.settingsImported == 0)
        }
    }

    /// Ice can hold both keys at once, since the V1 key survives its own
    /// migration. V2 wins outright: preferring the older key would undo an
    /// appearance change the user made in a later Ice build.
    @Test("With both appearance formats present, only V2 is imported")
    func v2AppearanceWinsWhenBothArePresent() throws {
        try withScratchDefaults { _ in
            let v2Data = try JSONEncoder().encode(markedV2Configuration)
            var v1Configuration = MenuBarAppearanceConfigurationV1.defaultConfiguration
            v1Configuration.shapeKind = .split
            v1Configuration.isInset = false
            let v1Data = try JSONEncoder().encode(v1Configuration)

            let (source, domainName) = try makeSource([
                "MenuBarAppearanceConfigurationV2": v2Data,
                "MenuBarAppearanceConfiguration": v1Data,
            ])
            defer { source.removePersistentDomain(forName: domainName) }

            var writes = [Data]()
            let importer = IceSettingsImporter(
                iceUserDefaults: source,
                iceDomainName: domainName,
                saveAppearanceConfiguration: { writes.append($0) }
            )

            let result = importer.importIceSettings()

            #expect(result.settingsImported == 1)
            #expect(writes.count == 1)
            #expect(writes.first == v2Data)

            // The V1 payload was deliberately given a different shape, so a
            // stored configuration carrying it would prove the fallback ran.
            let onlyWrite = try #require(writes.first)
            let stored = try JSONDecoder().decode(
                MenuBarAppearanceConfigurationV2.self,
                from: onlyWrite
            )
            #expect(stored == markedV2Configuration)
            #expect(stored.shapeKind != .split)
        }
    }
}
