//
//  IceSettingsImporterTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Ice settings importer")
@MainActor
struct IceSettingsImporterTests {
    @Test("A V1 appearance is converted and written as V2")
    func convertsV1Appearance() throws {
        var oldConfiguration = MenuBarAppearanceConfigurationV1.defaultConfiguration
        oldConfiguration.hasShadow = true
        oldConfiguration.hasBorder = true
        oldConfiguration.borderWidth = 3
        oldConfiguration.shapeKind = .full
        oldConfiguration.isInset = false

        let sourceData = try JSONEncoder().encode(oldConfiguration)
        let (source, domainName) = try makeSource(
            value: sourceData,
            forKey: "MenuBarAppearanceConfiguration"
        )
        defer { source.removePersistentDomain(forName: domainName) }

        var writtenData: Data?
        let importer = IceSettingsImporter(
            iceUserDefaults: source,
            iceDomainName: domainName,
            saveAppearanceConfiguration: { writtenData = $0 }
        )

        #expect(importer.hasIceSettings())
        let result = importer.importIceSettings()

        #expect(result.success)
        #expect(result.settingsImported == 1)
        let convertedData = try #require(writtenData)
        let converted = try JSONDecoder().decode(
            MenuBarAppearanceConfigurationV2.self,
            from: convertedData
        )
        #expect(converted.lightModeConfiguration.hasShadow)
        #expect(converted.darkModeConfiguration.hasBorder)
        #expect(converted.staticConfiguration.borderWidth == 3)
        #expect(converted.shapeKind == .full)
        #expect(!converted.isInset)
    }

    @Test("Malformed V1 appearance data is rejected without a write")
    func rejectsMalformedV1Appearance() throws {
        let (source, domainName) = try makeSource(
            value: Data("not-json".utf8),
            forKey: "MenuBarAppearanceConfiguration"
        )
        defer { source.removePersistentDomain(forName: domainName) }

        var writtenData: Data?
        let importer = IceSettingsImporter(
            iceUserDefaults: source,
            iceDomainName: domainName,
            saveAppearanceConfiguration: { writtenData = $0 }
        )

        let result = importer.importIceSettings()

        #expect(result.success)
        #expect(result.settingsImported == 0)
        #expect(writtenData == nil)
    }

    private func makeSource(
        value: Any,
        forKey key: String
    ) throws -> (defaults: UserDefaults, domainName: String) {
        let domainName = "com.stonerl.ThawTests.IceSettingsImporter.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domainName))
        defaults.set(value, forKey: key)
        return (defaults, domainName)
    }
}
