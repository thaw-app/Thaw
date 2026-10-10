//
//  SettingsResetter.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

extension AppSettings {
    func resetAllSettingsToDefaults() {
        resetGeneral()
        resetAdvanced()
        resetHotkeys()
        resetDisplay()
        resetAppearance()
        appState?.appRunningTriggers.reset()
        // Not a setting, but a learned verdict about the user's other apps.
        // A reset is the one moment they explicitly ask for a clean slate,
        // and it is the only way to clear a record from the UI.
        appState?.itemManager.failureLedger.removeAll()
    }

    func resetAppearance() {
        // appearanceManager lives on AppState, so the reset goes through it.
        appState?.appearanceManager.configuration = Defaults.DefaultValue.menuBarAppearanceConfigurationV2
    }

    func resetGeneral() {
        UserDefaults.standard.removeObject(forKey: AppUIZoom.defaultsKey)
        general.showThawIcon = Defaults.DefaultValue.showThawIcon
        general.thawIcon = Defaults.DefaultValue.thawIcon
        general.lastCustomThawIcon = nil
        general.customThawIconIsTemplate = Defaults.DefaultValue.customThawIconIsTemplate
        general.simpleMode = Defaults.DefaultValue.simpleMode
        general.showSettingDescriptions = Defaults.DefaultValue.showSettingDescriptions
        general.lockThawBarPosition = Defaults.DefaultValue.lockThawBarPosition
        general.enableThawBarOnly = Defaults.DefaultValue.enableThawBarOnly
        general.openHiddenItemsInMenuBar = Defaults.DefaultValue.openHiddenItemsInMenuBar
        general.roundScreenCorners = Defaults.DefaultValue.roundScreenCorners
        general.screenCornerRadius = Defaults.DefaultValue.screenCornerRadius
        general.showThawBarOnlyWithInlineReveal = Defaults.DefaultValue.showThawBarOnlyWithInlineReveal
        general.showThawBarOnlyLauncher = Defaults.DefaultValue.showThawBarOnlyLauncher
        general.useThawBar = Defaults.DefaultValue.useThawBar
        general.useThawBarOnlyOnNotchedDisplay = Defaults.DefaultValue.useThawBarOnlyOnNotchedDisplay
        general.thawBarLocation = Defaults.DefaultValue.thawBarLocation
        general.thawBarLocationOnHotkey = Defaults.DefaultValue.thawBarLocationOnHotkey
        general.showOnClick = Defaults.DefaultValue.showOnClick
        general.showOnHover = Defaults.DefaultValue.showOnHover
        general.showOnScroll = Defaults.DefaultValue.showOnScroll
        general.autoRehide = Defaults.DefaultValue.autoRehide
        general.rehideStrategy = Defaults.DefaultValue.rehideStrategy
        general.rehideInterval = Defaults.DefaultValue.rehideInterval
        general.tempShowInterval = Defaults.DefaultValue.tempShowInterval
    }

    func resetAdvanced() {
        advanced.enableAlwaysHiddenSection = Defaults.DefaultValue.enableAlwaysHiddenSection
        advanced.showAllSectionsOnUserDrag = Defaults.DefaultValue.showAllSectionsOnUserDrag
        appState?.itemManager.updateNewItemsPlacement(section: .hidden, arrangedViews: [])
        advanced.sectionDividerStyle = Defaults.DefaultValue.sectionDividerStyle
        advanced.menuBarArrangementMode = Defaults.DefaultValue.menuBarArrangementMode
        advanced.hideApplicationMenus = Defaults.DefaultValue.hideApplicationMenus
        advanced.enableSecondaryContextMenu = Defaults.DefaultValue.enableSecondaryContextMenu
        advanced.showOnHoverDelay = Defaults.DefaultValue.showOnHoverDelay
        advanced.tooltipDelay = Defaults.DefaultValue.tooltipDelay
        advanced.showMenuBarTooltips = Defaults.DefaultValue.showMenuBarTooltips
        advanced.iconRefreshInterval = Defaults.DefaultValue.iconRefreshInterval
        advanced.menuBarItemAlertRevealCooldown = Defaults.DefaultValue.menuBarItemAlertRevealCooldown
        advanced.autoZenWhileSharingScreen = Defaults.DefaultValue.autoZenWhileSharingScreen
        advanced.menuBarOrderFulfillmentTimeout = Defaults.DefaultValue.menuBarOrderFulfillmentTimeout
        advanced.enableDiagnosticLogging = Defaults.DefaultValue.enableDiagnosticLogging
        advanced.enableMenuBarItemOverflow = Defaults.DefaultValue.enableMenuBarItemOverflow
        advanced.enableExperimentalSystemItemHiding = Defaults.DefaultValue.enableExperimentalSystemItemHiding
        advanced.enableExperimentalOverflowPrevention = Defaults.DefaultValue.enableExperimentalOverflowPrevention
        advanced.alwaysUseAppIconForMenuBarItems = Defaults.DefaultValue.alwaysUseAppIconForMenuBarItems
        advanced.enableMenuBarItemDescenders = Defaults.DefaultValue.enableMenuBarItemDescenders
        advanced.enableSwapBar = Defaults.DefaultValue.enableSwapBar
        advanced.swapOnThawIconClick = Defaults.DefaultValue.swapOnThawIconClick
        advanced.fetchReleaseNotes = Defaults.DefaultValue.fetchReleaseNotes
        advanced.enableNativeAppHiding = Defaults.DefaultValue.enableNativeAppHiding
        advanced.enableModuleStandIns = Defaults.DefaultValue.enableModuleStandIns
        advanced.enableTimeMachineTakeover = Defaults.DefaultValue.enableTimeMachineTakeover
        advanced.enableTimerTakeover = Defaults.DefaultValue.enableTimerTakeover
        advanced.enableTextInputTakeover = Defaults.DefaultValue.enableTextInputTakeover
        advanced.enableRecordingWatch = Defaults.DefaultValue.enableRecordingWatch

        advanced.zenModeWhileRecording = Defaults.DefaultValue.zenModeWhileRecording
        advanced.recordingWatchScreen = Defaults.DefaultValue.recordingWatchScreen
        advanced.enableDesktopMenuHiding = Defaults.DefaultValue.enableDesktopMenuHiding
        advanced.searchSectionOrder = AdvancedSettings.sanitizedSearchSectionOrder(
            from: Defaults.DefaultValue.searchSectionOrder
        )
        advanced.searchIncludeVisible = Defaults.DefaultValue.searchIncludeVisible
        advanced.searchIncludeHidden = Defaults.DefaultValue.searchIncludeHidden
        advanced.searchIncludeAlwaysHidden = Defaults.DefaultValue.searchIncludeAlwaysHidden
        advanced.menuBarSearchPresentation = Defaults.DefaultValue.menuBarSearchPresentation
    }

    func resetHotkeys() {
        Defaults.set(Defaults.DefaultValue.hotkeys, forKey: .hotkeys)
        for hotkey in hotkeys.hotkeys {
            hotkey.keyCombination = nil
        }
    }

    func resetDisplay() {
        displaySettings.configurations = Defaults.DefaultValue.displayThawBarConfigurations
        displaySettings.globalConfiguration = Defaults.DefaultValue.globalDisplayConfiguration
        displaySettings.confirmSpacingRelaunch = Defaults.DefaultValue.confirmSpacingRelaunch
        displaySettings.unconfirmedSpacingProfileScope = Defaults.DefaultValue.unconfirmedSpacingProfileScope
        displaySettings.spacingApplyMode = Defaults.DefaultValue.spacingApplyMode
    }
}
