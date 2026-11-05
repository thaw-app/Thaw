//
//  AppLanguageTagTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// App language picks the shipped localization an AppleLanguages override names.
@MainActor
@Suite("App language selection")
struct AppLanguageTagTests {
    private let available = ["de", "en", "es", "pt-BR", "zh-Hans"]

    @Test("No override is System Default")
    func noOverride() {
        #expect(GeneralSettingsPane.languageTag(forOverride: nil, available: available) == GeneralSettingsPane.systemLanguageTag)
        #expect(GeneralSettingsPane.languageTag(forOverride: [], available: available) == GeneralSettingsPane.systemLanguageTag)
    }

    @Test(
        "An override maps onto a shipped localization",
        arguments: [("en", "en"), ("en-US", "en"), ("es-MX", "es"), ("pt-BR", "pt-BR"), ("zh-Hans", "zh-Hans")]
    )
    func mapsOverride(override: String, tag: String) {
        #expect(GeneralSettingsPane.languageTag(forOverride: [override], available: available) == tag)
    }

    @Test("A language Thaw doesn't ship is System Default")
    func unknownLanguage() {
        #expect(GeneralSettingsPane.languageTag(forOverride: ["fi-FI"], available: available) == GeneralSettingsPane.systemLanguageTag)
    }
}
