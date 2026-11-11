//
//  SettingsResetter.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import ThawUI

extension AppSettings {
    /// zoomDefaults holds the UI zoom, which @AppStorage keeps in the standard domain.
    func resetAllSettingsToDefaults(zoomDefaults: UserDefaults = .standard) {
        resetGeneral(zoomDefaults: zoomDefaults)
        resetLayout()
        resetVisibility()
        resetThawBar()
        resetScreenCorners()
        resetSpaces()
        resetPrivacy()
        resetTools()
        resetHotkeys()
        resetDisplay()
        resetAppearance()
        // Not a setting, but a learned verdict about the user's other apps.
        // A reset is the one moment they explicitly ask for a clean slate,
        // and it is the only way to clear a record from the UI.
        appState?.itemManager.failureLedger.removeAll()
        if let appState {
            let spaces = appState.spaceDirectory.spaces
            Task { await appState.spaceMenuBarKeeper.resetAll(spaces: spaces) }
        }
    }

    func resetAppearance() {
        // appearanceManager lives on AppState, so the reset goes through it.
        appState?.appearanceManager.configuration = Defaults.DefaultValue.menuBarAppearanceConfigurationV2
    }

    func resetGeneral(zoomDefaults: UserDefaults = .standard) {
        zoomDefaults.removeObject(forKey: AppUIZoom.defaultsKey)
        general.showThawIcon = Defaults.DefaultValue.showThawIcon
        general.thawIcon = Defaults.DefaultValue.thawIcon
        general.lastCustomThawIcon = nil
        general.customThawIconIsTemplate = Defaults.DefaultValue.customThawIconIsTemplate
        general.simpleMode = Defaults.DefaultValue.simpleMode
        general.simpleModeShowsPreview = Defaults.DefaultValue.simpleModeShowsPreview
        general.showSettingDescriptions = Defaults.DefaultValue.showSettingDescriptions
        general.settingsAppearance = .system
        general.hideApplicationMenus = Defaults.DefaultValue.hideApplicationMenus
        general.enableSecondaryContextMenu = Defaults.DefaultValue.enableSecondaryContextMenu
        general.enableDesktopMenuHiding = Defaults.DefaultValue.enableDesktopMenuHiding
    }

    func resetLayout() {
        layout.enableAlwaysHiddenSection = Defaults.DefaultValue.enableAlwaysHiddenSection
        layout.showAllSectionsOnUserDrag = Defaults.DefaultValue.showAllSectionsOnUserDrag
        appState?.itemManager.updateNewItemsPlacement(section: .hidden, arrangedViews: [])
        layout.sectionDividerStyle = Defaults.DefaultValue.sectionDividerStyle
        layout.customSectionDividerImage = nil
        layout.customSectionDividerIsTemplate = Defaults.DefaultValue.customSectionDividerIsTemplate
        layout.menuBarArrangementMode = Defaults.DefaultValue.menuBarArrangementMode
        layout.iconRefreshInterval = Defaults.DefaultValue.iconRefreshInterval
        layout.menuBarOrderFulfillmentTimeout = Defaults.DefaultValue.menuBarOrderFulfillmentTimeout
        layout.enableMenuBarItemOverflow = Defaults.DefaultValue.enableMenuBarItemOverflow
        layout.enableExperimentalOverflowPrevention = Defaults.DefaultValue.enableExperimentalOverflowPrevention
        layout.alwaysUseAppIconForMenuBarItems = Defaults.DefaultValue.alwaysUseAppIconForMenuBarItems
        layout.enableNativeAppHiding = Defaults.DefaultValue.enableNativeAppHiding
        layout.enableModuleStandIns = Defaults.DefaultValue.enableModuleStandIns
        layout.skippedModuleStandIns = Set(Defaults.DefaultValue.skippedModuleStandIns)
        layout.enableTimeMachineTakeover = Defaults.DefaultValue.enableTimeMachineTakeover
        layout.enableTimerTakeover = Defaults.DefaultValue.enableTimerTakeover
        layout.enableTextInputTakeover = Defaults.DefaultValue.enableTextInputTakeover
    }

    func resetVisibility() {
        visibility.showOnClick = Defaults.DefaultValue.showOnClick
        visibility.showOnHover = Defaults.DefaultValue.showOnHover
        visibility.showOnScroll = Defaults.DefaultValue.showOnScroll
        visibility.autoRehide = Defaults.DefaultValue.autoRehide
        visibility.rehideStrategy = Defaults.DefaultValue.rehideStrategy
        visibility.rehideInterval = Defaults.DefaultValue.rehideInterval
        visibility.tempShowInterval = Defaults.DefaultValue.tempShowInterval
        visibility.showOnHoverDelay = Defaults.DefaultValue.showOnHoverDelay
        visibility.tooltipDelay = Defaults.DefaultValue.tooltipDelay
        visibility.showMenuBarTooltips = Defaults.DefaultValue.showMenuBarTooltips
        visibility.autoZenWhileSharingScreen = Defaults.DefaultValue.autoZenWhileSharingScreen
        visibility.enableMenuBarItemDescenders = Defaults.DefaultValue.enableMenuBarItemDescenders
        visibility.enableSwapBar = Defaults.DefaultValue.enableSwapBar
        visibility.swapOnThawIconClick = Defaults.DefaultValue.swapOnThawIconClick
        visibility.showAlwaysHiddenOnIconDoubleClick = Defaults.DefaultValue.showAlwaysHiddenOnIconDoubleClick
        visibility.enableRecordingWatch = Defaults.DefaultValue.enableRecordingWatch
        visibility.zenModeWhileRecording = Defaults.DefaultValue.zenModeWhileRecording
        visibility.recordingWatchScreen = Defaults.DefaultValue.recordingWatchScreen
        visibility.menuBarSearchPresentation = Defaults.DefaultValue.menuBarSearchPresentation
        Defaults.set(Defaults.DefaultValue.showSearchShortcutBar, forKey: .showSearchShortcutBar)
    }

    func resetThawBar() {
        thawBar.lockThawBarPosition = Defaults.DefaultValue.lockThawBarPosition
        thawBar.openHiddenItemsInMenuBar = Defaults.DefaultValue.openHiddenItemsInMenuBar
        thawBar.useThawBar = Defaults.DefaultValue.useThawBar
        thawBar.useThawBarOnlyOnNotchedDisplay = Defaults.DefaultValue.useThawBarOnlyOnNotchedDisplay
        thawBar.thawBarLocation = Defaults.DefaultValue.thawBarLocation
        thawBar.thawBarLocationOnHotkey = Defaults.DefaultValue.thawBarLocationOnHotkey
    }

    func resetScreenCorners() {
        appearance.roundScreenCorners = Defaults.DefaultValue.roundScreenCorners
        appearance.screenCornerRadius = Defaults.DefaultValue.screenCornerRadius
    }

    func resetSpaces() {
        spaces.showSpaceIndicator = Defaults.DefaultValue.showSpaceIndicator
    }

    func resetPrivacy() {
        privacy.fetchReleaseNotes = Defaults.DefaultValue.fetchReleaseNotes
        privacy.showReleaseNotesAfterUpdate = Defaults.DefaultValue.showReleaseNotesAfterUpdate
    }

    func resetTools() {
        tools.enableDiagnosticLogging = Defaults.DefaultValue.enableDiagnosticLogging
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
        displaySettings.wideDisplayRule.isEnabled = Defaults.DefaultValue.showEveryItemOnWideDisplays
        displaySettings.wideDisplayRule.minimumWidth = Defaults.DefaultValue.wideDisplayMinimumWidth
    }
}
