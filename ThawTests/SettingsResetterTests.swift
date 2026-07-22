//
//  SettingsResetterTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Settings reset")
struct SettingsResetterTests {
    @Test("Advanced reset restores every previously omitted preference")
    @MainActor
    func advancedResetRestoresOmittedPreferences() {
        let settings = AppSettings()
        let advanced = settings.advanced

        advanced.useOptionClickToShowAlwaysHiddenSection = !Defaults.DefaultValue.useOptionClickToShowAlwaysHiddenSection
        advanced.useDoubleClickToShowAlwaysHiddenSection = !Defaults.DefaultValue.useDoubleClickToShowAlwaysHiddenSection
        advanced.enableSecondaryContextMenuQuit = !Defaults.DefaultValue.enableSecondaryContextMenuQuit
        advanced.useLCSSortingOnNotchedDisplays = !Defaults.DefaultValue.useLCSSortingOnNotchedDisplays
        advanced.enableMenuBarItemOverflow = !Defaults.DefaultValue.enableMenuBarItemOverflow
        advanced.enableExperimentalSystemItemHiding = !Defaults.DefaultValue.enableExperimentalSystemItemHiding
        advanced.enableExperimentalWindowHiding = !Defaults.DefaultValue.enableExperimentalWindowHiding
        advanced.enableExperimentalOverflowPrevention = !Defaults.DefaultValue.enableExperimentalOverflowPrevention
        advanced.alwaysUseAppIconForMenuBarItems = !Defaults.DefaultValue.alwaysUseAppIconForMenuBarItems

        settings.resetAdvanced()

        #expect(advanced.useOptionClickToShowAlwaysHiddenSection == Defaults.DefaultValue.useOptionClickToShowAlwaysHiddenSection)
        #expect(advanced.useDoubleClickToShowAlwaysHiddenSection == Defaults.DefaultValue.useDoubleClickToShowAlwaysHiddenSection)
        #expect(advanced.enableSecondaryContextMenuQuit == Defaults.DefaultValue.enableSecondaryContextMenuQuit)
        #expect(advanced.useLCSSortingOnNotchedDisplays == Defaults.DefaultValue.useLCSSortingOnNotchedDisplays)
        #expect(advanced.enableMenuBarItemOverflow == Defaults.DefaultValue.enableMenuBarItemOverflow)
        #expect(advanced.enableExperimentalSystemItemHiding == Defaults.DefaultValue.enableExperimentalSystemItemHiding)
        #expect(advanced.enableExperimentalWindowHiding == Defaults.DefaultValue.enableExperimentalWindowHiding)
        #expect(advanced.enableExperimentalOverflowPrevention == Defaults.DefaultValue.enableExperimentalOverflowPrevention)
        #expect(advanced.alwaysUseAppIconForMenuBarItems == Defaults.DefaultValue.alwaysUseAppIconForMenuBarItems)
    }
}
