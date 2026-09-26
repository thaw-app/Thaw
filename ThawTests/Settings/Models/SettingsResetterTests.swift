//
//  SettingsResetterTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers ``AppSettings``' reset surface: every reset returns the properties
/// it owns to `Defaults.DefaultValue` and stays inside its own pane.
///
/// Built without an `AppState`, so the `appState?.…` hops in
/// `resetAppearance()` and `resetAdvanced()` are no-ops here.
///
/// Uses `withScratchDefaults`, not an `init`/`deinit` snapshot of the real
/// domain: that ran per test and raced every other suite reading `Defaults`.
@MainActor
@Suite("Settings resetter")
struct SettingsResetterTests {
    /// Builds an `AppSettings` inside a scratch store. It reads `Defaults` in
    /// its initializer, so it has to be constructed after the swap.
    private func withSettings(_ body: (AppSettings) throws -> Void) throws {
        try withScratchDefaults { _ in
            try body(AppSettings())
        }
    }

    // MARK: General

    @Test("Resetting General restores its defaults")
    func resetGeneralRestoresDefaults() throws {
        try withSettings { settings in
            settings.general.showIceIcon = !Defaults.DefaultValue.showIceIcon
            settings.general.showOnHover = !Defaults.DefaultValue.showOnHover
            settings.general.autoRehide = !Defaults.DefaultValue.autoRehide
            settings.general.hideDockIconWhenToggling = !Defaults.DefaultValue.hideDockIconWhenToggling
            settings.general.rehideInterval = Defaults.DefaultValue.rehideInterval + 42

            settings.resetGeneral()

            #expect(settings.general.showIceIcon == Defaults.DefaultValue.showIceIcon)
            #expect(settings.general.showOnHover == Defaults.DefaultValue.showOnHover)
            #expect(settings.general.autoRehide == Defaults.DefaultValue.autoRehide)
            #expect(settings.general.hideDockIconWhenToggling == Defaults.DefaultValue.hideDockIconWhenToggling)
            #expect(settings.general.rehideInterval == Defaults.DefaultValue.rehideInterval)
            #expect(settings.general.lastCustomIceIcon == nil)
        }
    }

    @Test("Resetting General leaves Advanced alone")
    func resetGeneralDoesNotTouchAdvanced() throws {
        try withSettings { settings in
            let changed = !Defaults.DefaultValue.hideApplicationMenus
            settings.advanced.hideApplicationMenus = changed

            settings.resetGeneral()

            #expect(settings.advanced.hideApplicationMenus == changed)
        }
    }

    // MARK: Advanced

    @Test("Resetting Advanced restores its defaults")
    func resetAdvancedRestoresDefaults() throws {
        try withSettings { settings in
            settings.advanced.hideApplicationMenus = !Defaults.DefaultValue.hideApplicationMenus
            settings.advanced.enableAlwaysHiddenSection = !Defaults.DefaultValue.enableAlwaysHiddenSection
            settings.advanced.showMenuBarTooltips = !Defaults.DefaultValue.showMenuBarTooltips
            settings.advanced.tooltipDelay = Defaults.DefaultValue.tooltipDelay + 5

            settings.resetAdvanced()

            #expect(settings.advanced.hideApplicationMenus == Defaults.DefaultValue.hideApplicationMenus)
            #expect(settings.advanced.enableAlwaysHiddenSection == Defaults.DefaultValue.enableAlwaysHiddenSection)
            #expect(settings.advanced.showMenuBarTooltips == Defaults.DefaultValue.showMenuBarTooltips)
            #expect(settings.advanced.tooltipDelay == Defaults.DefaultValue.tooltipDelay)
        }
    }

    @Test("Resetting Advanced restores the sanitized search section order")
    func resetAdvancedRestoresSearchSectionOrder() throws {
        try withSettings { settings in
            settings.advanced.searchSectionOrder = []

            settings.resetAdvanced()

            let expected = AdvancedSettings.sanitizedSearchSectionOrder(
                from: Defaults.DefaultValue.searchSectionOrder
            )
            #expect(settings.advanced.searchSectionOrder == expected)
            #expect(!settings.advanced.searchSectionOrder.isEmpty)
        }
    }

    /// `resetAdvanced()` once omitted persisted booleans, leaving them as the
    /// user set them. `hideApplicationMenus` and `showMenuBarTooltips` stay in
    /// as controls. Any boolean added to `AdvancedSettings` belongs in both
    /// `resetAdvanced()` and this test.
    @Test("Resetting Advanced restores every persisted boolean")
    func resetAdvancedRestoresEveryBoolean() throws {
        try withSettings { settings in
            // Previously omitted booleans: flip each off its default.
            settings.advanced.useOptionClickToShowAlwaysHiddenSection = !Defaults.DefaultValue.useOptionClickToShowAlwaysHiddenSection
            settings.advanced.useDoubleClickToShowAlwaysHiddenSection = !Defaults.DefaultValue.useDoubleClickToShowAlwaysHiddenSection
            settings.advanced.enableSecondaryContextMenuQuit = !Defaults.DefaultValue.enableSecondaryContextMenuQuit
            settings.advanced.enableMenuBarItemOverflow = !Defaults.DefaultValue.enableMenuBarItemOverflow
            settings.advanced.useThawBarOnNotchOverflow = !Defaults.DefaultValue.useThawBarOnNotchOverflow
            settings.advanced.useAXClickDelivery = !Defaults.DefaultValue.useAXClickDelivery
            settings.advanced.automaticArrangementEnabled = !Defaults.DefaultValue.automaticArrangementEnabled
            settings.advanced.moveCursorToRevealedItem = !Defaults.DefaultValue.moveCursorToRevealedItem
            // Controls that already reset before the fix.
            settings.advanced.hideApplicationMenus = !Defaults.DefaultValue.hideApplicationMenus
            settings.advanced.showMenuBarTooltips = !Defaults.DefaultValue.showMenuBarTooltips

            settings.resetAdvanced()

            #expect(settings.advanced.useOptionClickToShowAlwaysHiddenSection == Defaults.DefaultValue.useOptionClickToShowAlwaysHiddenSection)
            #expect(settings.advanced.useDoubleClickToShowAlwaysHiddenSection == Defaults.DefaultValue.useDoubleClickToShowAlwaysHiddenSection)
            #expect(settings.advanced.enableSecondaryContextMenuQuit == Defaults.DefaultValue.enableSecondaryContextMenuQuit)
            #expect(settings.advanced.enableMenuBarItemOverflow == Defaults.DefaultValue.enableMenuBarItemOverflow)
            #expect(settings.advanced.useThawBarOnNotchOverflow == Defaults.DefaultValue.useThawBarOnNotchOverflow)
            #expect(settings.advanced.useAXClickDelivery == Defaults.DefaultValue.useAXClickDelivery)
            #expect(settings.advanced.automaticArrangementEnabled == Defaults.DefaultValue.automaticArrangementEnabled)
            #expect(settings.advanced.moveCursorToRevealedItem == Defaults.DefaultValue.moveCursorToRevealedItem)
            #expect(settings.advanced.hideApplicationMenus == Defaults.DefaultValue.hideApplicationMenus)
            #expect(settings.advanced.showMenuBarTooltips == Defaults.DefaultValue.showMenuBarTooltips)
        }
    }

    // MARK: Hotkeys

    @Test("Resetting Hotkeys clears every binding")
    func resetHotkeysClearsBindings() throws {
        try withSettings { settings in
            let hotkey = try #require(settings.hotkeys.hotkey(withAction: .toggleHiddenSection))
            hotkey.keyCombination = KeyCombination(key: .f19, modifiers: [.command, .shift])

            settings.resetHotkeys()

            #expect(settings.hotkeys.hotkeys.allSatisfy { $0.keyCombination == nil })
        }
    }

    // MARK: Display

    @Test("Resetting Display restores its defaults")
    func resetDisplayRestoresDefaults() throws {
        try withSettings { settings in
            settings.displaySettings.configurations = [
                "UUID-A": .defaultConfiguration.withItemSpacingOffset(9),
            ]
            settings.displaySettings.globalConfiguration = .defaultConfiguration.withItemSpacingOffset(-9)
            settings.displaySettings.confirmSpacingRelaunch = !Defaults.DefaultValue.confirmSpacingRelaunch
            // Default is `.activeProfile`, so this has to be moved off it for the
            // assertion below to mean anything.
            settings.displaySettings.unconfirmedSpacingProfileScope = .allProfiles
            settings.displaySettings.spacingApplyMode = .writeOnly

            settings.resetDisplay()

            #expect(settings.displaySettings.configurations == Defaults.DefaultValue.displayIceBarConfigurations)
            #expect(settings.displaySettings.globalConfiguration == Defaults.DefaultValue.globalDisplayConfiguration)
            #expect(settings.displaySettings.confirmSpacingRelaunch == Defaults.DefaultValue.confirmSpacingRelaunch)
            #expect(
                settings.displaySettings.unconfirmedSpacingProfileScope
                    == Defaults.DefaultValue.unconfirmedSpacingProfileScope
            )
            #expect(settings.displaySettings.spacingApplyMode == Defaults.DefaultValue.spacingApplyMode)
        }
    }

    // MARK: All

    @Test("Resetting everything covers every pane at once")
    func resetAllRestoresEveryPane() throws {
        try withSettings { settings in
            settings.general.showOnHover = !Defaults.DefaultValue.showOnHover
            settings.advanced.hideApplicationMenus = !Defaults.DefaultValue.hideApplicationMenus
            settings.displaySettings.confirmSpacingRelaunch = !Defaults.DefaultValue.confirmSpacingRelaunch

            settings.resetAllSettingsToDefaults()

            #expect(settings.general.showOnHover == Defaults.DefaultValue.showOnHover)
            #expect(settings.advanced.hideApplicationMenus == Defaults.DefaultValue.hideApplicationMenus)
            #expect(settings.displaySettings.confirmSpacingRelaunch == Defaults.DefaultValue.confirmSpacingRelaunch)
            #expect(settings.hotkeys.hotkeys.allSatisfy { $0.keyCombination == nil })
        }
    }

    @Test("Resetting is idempotent")
    func resetIsIdempotent() throws {
        try withSettings { settings in
            settings.resetAllSettingsToDefaults()
            let firstPass = settings.general.showOnHover

            settings.resetAllSettingsToDefaults()

            #expect(settings.general.showOnHover == firstPass)
            #expect(settings.general.showOnHover == Defaults.DefaultValue.showOnHover)
        }
    }
}
