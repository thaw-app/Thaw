//
//  IceSettingsImporterPerDisplayTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Testing
@testable import Thaw

/// Covers the per-display half of the Ice import: when the source domain has
/// `UseIceBar` enabled, the importer must synthesize a
/// `DisplayIceBarConfiguration` for every connected display so the migrated
/// setting actually takes effect in Thaw's per-display model.
///
/// `buildConfigurations` walks the real `NSScreen` list, which hosted tests
/// have at least one of, so the generated dictionary is asserted non-empty
/// rather than against a fixed display count.
///
/// Like the sibling importer suites, every case runs inside
/// `withScratchDefaults` and the suite is `.serialized`: `Defaults.store` is
/// process-wide.
@Suite("Ice settings importer: per-display generation", .serialized)
@MainActor
struct IceSettingsImporterPerDisplayTests {
    @Test("UseIceBar in the source generates per-display configurations")
    func useIceBarGeneratesConfigurations() throws {
        try withScratchDefaults { _ in
            let (source, domainName) = try makeSource([
                "UseIceBar": true,
                "IceBarLocation": 1,
            ])
            defer { source.removePersistentDomain(forName: domainName) }

            let importer = IceSettingsImporter(
                iceUserDefaults: source,
                iceDomainName: domainName,
                saveAppearanceConfiguration: { _ in }
            )
            let result = importer.importIceSettings()

            #expect(result.success)
            // UseIceBar + IceBarLocation as plain key copies, plus the
            // generated per-display block.
            #expect(result.settingsImported >= 3)

            let data = try #require(Defaults.data(forKey: .displayIceBarConfigurations))
            let configs = try JSONDecoder()
                .decode([String: DisplayIceBarConfiguration].self, from: data)
            // Every connected display must come out of the migration with a
            // configuration, keyed by its UUID — no more, no less.
            let connectedUUIDs = Set(NSScreen.screens.compactMap {
                Bridging.getDisplayUUIDString(for: $0.displayID)
            })
            #expect(!connectedUUIDs.isEmpty)
            #expect(Set(configs.keys) == connectedUUIDs)
            // Hoisted out of #expect: the macro cannot infer that the
            // key-path overload of the rethrowing allSatisfy does not throw,
            // and swiftformat's preferKeyPath rewrites the closure form.
            let allUseIceBar = configs.values.allSatisfy(\.useIceBar)
            #expect(allUseIceBar)
            let expectedLocation = try #require(IceBarLocation(rawValue: 1))
            #expect(configs.values.allSatisfy { $0.iceBarLocation == expectedLocation })
            #expect(Defaults.bool(forKey: .hasMigratedPerDisplayIceBar))
        }
    }

    @Test("A source without UseIceBar generates nothing")
    func absentUseIceBarGeneratesNothing() throws {
        try withScratchDefaults { _ in
            let (source, domainName) = try makeSource(["ShowIceIcon": true])
            defer { source.removePersistentDomain(forName: domainName) }

            let importer = IceSettingsImporter(
                iceUserDefaults: source,
                iceDomainName: domainName,
                saveAppearanceConfiguration: { _ in }
            )
            let result = importer.importIceSettings()

            #expect(result.success)
            #expect(Defaults.data(forKey: .displayIceBarConfigurations) == nil)
            #expect(!Defaults.bool(forKey: .hasMigratedPerDisplayIceBar))
        }
    }

    // MARK: Helpers

    private func makeSource(
        _ values: [String: Any]
    ) throws -> (defaults: UserDefaults, domainName: String) {
        let domainName = "com.stonerl.ThawTests.IceSettingsImporter.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domainName))
        for (key, value) in values {
            defaults.set(value, forKey: key)
        }
        return (defaults, domainName)
    }
}
