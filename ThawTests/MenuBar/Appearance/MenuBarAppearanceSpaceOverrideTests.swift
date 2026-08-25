//
//  MenuBarAppearanceSpaceOverrideTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import Testing

@Suite("Menu bar appearance Space overrides")
struct MenuBarAppearanceSpaceOverrideTests {
    private func makeConfiguration(tintKind: MenuBarTintKind) -> MenuBarAppearanceConfigurationV2 {
        var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        configuration.staticConfiguration.tintKind = tintKind
        configuration.lightModeConfiguration.tintKind = tintKind
        configuration.darkModeConfiguration.tintKind = tintKind
        return configuration
    }

    @Test("A Space with no override falls back to the shared base")
    func fallsBackToBase() {
        let base = makeConfiguration(tintKind: .solid)
        let resolved = MenuBarAppearanceManager.effectiveConfiguration(
            base: base,
            overrides: [:],
            activeSpaceID: 42
        )
        #expect(resolved == base)
    }

    @Test("The active Space's override wins over the base")
    func overrideWins() {
        let base = makeConfiguration(tintKind: .solid)
        let overridden = makeConfiguration(tintKind: .noTint)
        let resolved = MenuBarAppearanceManager.effectiveConfiguration(
            base: base,
            overrides: ["42": overridden],
            activeSpaceID: 42
        )
        #expect(resolved == overridden)
    }

    @Test("Other Spaces' overrides do not leak into the active Space")
    func otherSpacesDoNotLeak() {
        let base = makeConfiguration(tintKind: .solid)
        let overridden = makeConfiguration(tintKind: .noTint)
        let resolved = MenuBarAppearanceManager.effectiveConfiguration(
            base: base,
            overrides: ["7": overridden],
            activeSpaceID: 42
        )
        #expect(resolved == base)
    }
}
