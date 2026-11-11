//
//  PreferenceModelsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import Testing
@testable import Thaw
import ThawUI

/// The page settings models on their own, with settings in a throwaway
/// suite. None is wired to an AppState, so no change reaches the menu bar.
@MainActor
@Suite("Preference models", .serialized, .scratchDefaults)
struct PreferenceModelsTests {
    private func uriChange(_ key: String, _ info: [String: Any]) -> Notification {
        var userInfo = info
        userInfo["key"] = key
        return Notification(name: .settingsDidChangeViaURI, userInfo: userInfo)
    }

    // MARK: General

    @Test("General settings write each change through to Defaults")
    func generalPersists() {
        let settings = GeneralSettings()
        settings.showThawIcon = false
        settings.customThawIconIsTemplate = !Defaults.DefaultValue.customThawIconIsTemplate
        settings.simpleMode = !Defaults.DefaultValue.simpleMode
        settings.showSettingDescriptions = !Defaults.DefaultValue.showSettingDescriptions
        settings.settingsAppearance = .black
        settings.simpleModeShowsPreview = !Defaults.DefaultValue.simpleModeShowsPreview
        settings.hideApplicationMenus = !Defaults.DefaultValue.hideApplicationMenus
        settings.enableSecondaryContextMenu = !Defaults.DefaultValue.enableSecondaryContextMenu
        settings.enableDesktopMenuHiding = !Defaults.DefaultValue.enableDesktopMenuHiding

        #expect(Defaults.bool(forKey: .showThawIcon) == false)

        let reloaded = GeneralSettings()
        reloaded.loadInitialState()
        #expect(reloaded.showThawIcon == false)
        #expect(reloaded.customThawIconIsTemplate == settings.customThawIconIsTemplate)
        #expect(reloaded.simpleMode == settings.simpleMode)
        #expect(reloaded.showSettingDescriptions == settings.showSettingDescriptions)
        #expect(reloaded.settingsAppearance == .black)
        #expect(reloaded.simpleModeShowsPreview == settings.simpleModeShowsPreview)
        #expect(reloaded.hideApplicationMenus == settings.hideApplicationMenus)
        #expect(reloaded.enableSecondaryContextMenu == settings.enableSecondaryContextMenu)
        #expect(reloaded.enableDesktopMenuHiding == settings.enableDesktopMenuHiding)
    }

    @Test("A custom icon is remembered as the last custom icon and survives a reload")
    func customIconRemembered() {
        let settings = GeneralSettings()
        let custom = ControlItemImageSet(name: .custom, image: .data(Data([1, 2, 3])))
        settings.thawIcon = custom
        #expect(settings.lastCustomThawIcon == custom)
        #expect(settings.takeThawIconPersistenceError() == nil)

        let reloaded = GeneralSettings()
        reloaded.loadInitialState()
        #expect(reloaded.thawIcon == custom)
        #expect(reloaded.lastCustomThawIcon == custom)
    }

    @Test("An icon or enum value that cannot be read leaves the defaults")
    func generalIgnoresGarbage() {
        Defaults.set(Data("x".utf8), forKey: .thawIcon)
        Defaults.set(99, forKey: .thawBarLocation)
        Defaults.set(99, forKey: .rehideStrategy)
        let general = GeneralSettings()
        general.loadInitialState()
        let thawBar = ThawBarSettings()
        thawBar.loadInitialState()
        let visibility = VisibilitySettings()
        visibility.loadInitialState()
        #expect(general.thawIcon == Defaults.DefaultValue.thawIcon)
        #expect(thawBar.thawBarLocation == Defaults.DefaultValue.thawBarLocation)
        #expect(visibility.rehideStrategy == Defaults.DefaultValue.rehideStrategy)
    }

    @Test("General URI changes set the matching property and ignore everything else")
    func generalURIChanges() async {
        let appState = AppState()
        let settings = GeneralSettings()
        settings.performSetup(with: appState)
        let paths: [String: ReferenceWritableKeyPath<GeneralSettings, Bool>] = [
            "showThawIcon": \.showThawIcon, "customThawIconIsTemplate": \.customThawIconIsTemplate,
            "simpleMode": \.simpleMode, "showSettingDescriptions": \.showSettingDescriptions,
            "hideApplicationMenus": \.hideApplicationMenus, "enableSecondaryContextMenu": \.enableSecondaryContextMenu,
            "enableDesktopMenuHiding": \.enableDesktopMenuHiding,
        ]
        for (key, path) in paths {
            let flipped = !settings[keyPath: path]
            NotificationCenter.default.post(uriChange(key, ["value": flipped]))
            await waitUntil { settings[keyPath: path] == flipped }
            #expect(settings[keyPath: path] == flipped, "\(key) follows the URI")
        }

        NotificationCenter.default.post(uriChange("settingsAppearance", ["rawEnumValue": SettingsAppearance.black.rawValue]))
        await waitUntil { settings.settingsAppearance == .black }
        #expect(settings.settingsAppearance == .black)

        NotificationCenter.default.post(uriChange("settingsAppearance", ["rawEnumValue": 42]))
        NotificationCenter.default.post(uriChange("unknown", ["value": true, "doubleValue": 1.0]))
        NotificationCenter.default.post(Notification(name: .settingsDidChangeViaURI, userInfo: ["value": true]))
        NotificationCenter.default.post(uriChange("showThawIcon", ["value": !settings.showThawIcon]))
        let expected = !settings.showThawIcon
        await waitUntil { settings.showThawIcon == expected }
        #expect(settings.settingsAppearance == .black, "an unknown raw value changes nothing")
    }

    // MARK: Visibility, Thaw Bar and screen corners

    @Test("Visibility, Thaw Bar and screen-corner settings write through to Defaults and load back")
    func visibilityThawBarAndCornersPersist() {
        let visibility = VisibilitySettings()
        visibility.showOnClick = !Defaults.DefaultValue.showOnClick
        visibility.showOnHover = !Defaults.DefaultValue.showOnHover
        visibility.showOnScroll = !Defaults.DefaultValue.showOnScroll
        visibility.autoRehide = !Defaults.DefaultValue.autoRehide
        visibility.rehideStrategy = .focusedApp
        visibility.rehideInterval = 42
        visibility.tempShowInterval = 7
        visibility.showOnHoverDelay = 0.9
        visibility.tooltipDelay = 1.1
        visibility.showMenuBarTooltips = !Defaults.DefaultValue.showMenuBarTooltips
        visibility.autoZenWhileSharingScreen = !Defaults.DefaultValue.autoZenWhileSharingScreen
        visibility.enableMenuBarItemDescenders = !Defaults.DefaultValue.enableMenuBarItemDescenders
        visibility.enableSwapBar = !Defaults.DefaultValue.enableSwapBar
        visibility.swapOnThawIconClick = !Defaults.DefaultValue.swapOnThawIconClick
        visibility.enableRecordingWatch = !Defaults.DefaultValue.enableRecordingWatch
        visibility.zenModeWhileRecording = !Defaults.DefaultValue.zenModeWhileRecording
        visibility.recordingWatchScreen = .mainDisplay
        visibility.recordingWatchPlacement = .leading
        visibility.menuBarSearchPresentation = .compact
        let thawBar = ThawBarSettings()
        thawBar.lockThawBarPosition = !Defaults.DefaultValue.lockThawBarPosition
        thawBar.openHiddenItemsInMenuBar = !Defaults.DefaultValue.openHiddenItemsInMenuBar
        thawBar.useThawBar = !Defaults.DefaultValue.useThawBar
        thawBar.useThawBarOnlyOnNotchedDisplay = !Defaults.DefaultValue.useThawBarOnlyOnNotchedDisplay
        thawBar.thawBarLocation = .leftAligned
        thawBar.thawBarLocationOnHotkey = !Defaults.DefaultValue.thawBarLocationOnHotkey
        let corners = AppearanceSettings()
        corners.roundScreenCorners = !Defaults.DefaultValue.roundScreenCorners
        corners.screenCornerRadius = 22

        #expect(Defaults.double(forKey: .screenCornerRadius) == 22)
        #expect(Defaults.integer(forKey: .thawBarLocation) == ThawBarLocation.leftAligned.rawValue)
        #expect(Defaults.integer(forKey: .rehideStrategy) == RehideStrategy.focusedApp.rawValue)
        #expect(Defaults.string(forKey: .recordingWatchScreen) == "mainDisplay")

        let reloadedVisibility = VisibilitySettings()
        reloadedVisibility.loadInitialState()
        #expect(reloadedVisibility.showOnClick == visibility.showOnClick)
        #expect(reloadedVisibility.showOnHover == visibility.showOnHover)
        #expect(reloadedVisibility.showOnScroll == visibility.showOnScroll)
        #expect(reloadedVisibility.autoRehide == visibility.autoRehide)
        #expect(reloadedVisibility.rehideStrategy == .focusedApp)
        #expect(reloadedVisibility.rehideInterval == 42)
        #expect(reloadedVisibility.tempShowInterval == 7)
        #expect(reloadedVisibility.showOnHoverDelay == 0.9)
        #expect(reloadedVisibility.tooltipDelay == 1.1)
        #expect(reloadedVisibility.showMenuBarTooltips == visibility.showMenuBarTooltips)
        #expect(reloadedVisibility.autoZenWhileSharingScreen == visibility.autoZenWhileSharingScreen)
        #expect(reloadedVisibility.enableMenuBarItemDescenders == visibility.enableMenuBarItemDescenders)
        #expect(reloadedVisibility.enableSwapBar == visibility.enableSwapBar)
        #expect(reloadedVisibility.swapOnThawIconClick == visibility.swapOnThawIconClick)
        #expect(reloadedVisibility.enableRecordingWatch == visibility.enableRecordingWatch)
        #expect(reloadedVisibility.zenModeWhileRecording == visibility.zenModeWhileRecording)
        #expect(reloadedVisibility.recordingWatchScreen == .mainDisplay)
        #expect(reloadedVisibility.recordingWatchPlacement == .leading)
        #expect(reloadedVisibility.menuBarSearchPresentation == .compact)

        let reloadedThawBar = ThawBarSettings()
        reloadedThawBar.loadInitialState()
        #expect(reloadedThawBar.lockThawBarPosition == thawBar.lockThawBarPosition)
        #expect(reloadedThawBar.openHiddenItemsInMenuBar == thawBar.openHiddenItemsInMenuBar)
        #expect(reloadedThawBar.useThawBar == thawBar.useThawBar)
        #expect(reloadedThawBar.useThawBarOnlyOnNotchedDisplay == thawBar.useThawBarOnlyOnNotchedDisplay)
        #expect(reloadedThawBar.thawBarLocation == .leftAligned)
        #expect(reloadedThawBar.thawBarLocationOnHotkey == thawBar.thawBarLocationOnHotkey)

        let reloadedCorners = AppearanceSettings()
        reloadedCorners.loadInitialState()
        #expect(reloadedCorners.roundScreenCorners == corners.roundScreenCorners)
        #expect(reloadedCorners.screenCornerRadius == 22)
    }

    @Test("Visibility and Thaw Bar URI changes set the matching property and ignore everything else")
    func visibilityAndThawBarURIChanges() {
        let visibility = VisibilitySettings()
        let bools: [String: ReferenceWritableKeyPath<VisibilitySettings, Bool>] = [
            "showOnClick": \.showOnClick, "showOnHover": \.showOnHover, "showOnScroll": \.showOnScroll,
            "autoRehide": \.autoRehide, "showMenuBarTooltips": \.showMenuBarTooltips,
            "autoZenWhileSharingScreen": \.autoZenWhileSharingScreen,
            "enableMenuBarItemDescenders": \.enableMenuBarItemDescenders, "enableSwapBar": \.enableSwapBar,
            "swapOnThawIconClick": \.swapOnThawIconClick,
            "showAlwaysHiddenOnIconDoubleClick": \.showAlwaysHiddenOnIconDoubleClick,
            "enableRecordingWatch": \.enableRecordingWatch, "zenModeWhileRecording": \.zenModeWhileRecording,
        ]
        for (key, path) in bools {
            let flipped = !visibility[keyPath: path]
            visibility.handleExternalSettingsChange(uriChange(key, ["value": flipped]))
            #expect(visibility[keyPath: path] == flipped, "\(key) follows the URI")
        }
        let doubles: [String: ReferenceWritableKeyPath<VisibilitySettings, Double>] = [
            "showOnHoverDelay": \.showOnHoverDelay, "tooltipDelay": \.tooltipDelay,
            "rehideInterval": \.rehideInterval, "tempShowInterval": \.tempShowInterval,
        ]
        for (key, path) in doubles {
            visibility.handleExternalSettingsChange(uriChange(key, ["doubleValue": 4.5]))
            #expect(visibility[keyPath: path] == 4.5, "\(key) follows the URI")
        }
        visibility.handleExternalSettingsChange(uriChange("rehideStrategy", ["rawEnumValue": RehideStrategy.timed.rawValue]))
        #expect(visibility.rehideStrategy == .timed)
        visibility.handleExternalSettingsChange(uriChange("rehideStrategy", ["rawEnumValue": 42]))
        #expect(visibility.rehideStrategy == .timed, "an unknown raw value changes nothing")

        let thawBar = ThawBarSettings()
        let thawBarPaths: [String: ReferenceWritableKeyPath<ThawBarSettings, Bool>] = [
            "lockThawBarPosition": \.lockThawBarPosition, "openHiddenItemsInMenuBar": \.openHiddenItemsInMenuBar,
            "useThawBarOnlyOnNotchedDisplay": \.useThawBarOnlyOnNotchedDisplay,
            "thawBarLocationOnHotkey": \.thawBarLocationOnHotkey,
        ]
        for (key, path) in thawBarPaths {
            let flipped = !thawBar[keyPath: path]
            thawBar.handleExternalSettingsChange(uriChange(key, ["value": flipped]))
            #expect(thawBar[keyPath: path] == flipped, "\(key) follows the URI")
        }
        let before = visibility.tooltipDelay
        visibility.handleExternalSettingsChange(uriChange("unknown", ["value": true, "doubleValue": 8.0]))
        visibility.handleExternalSettingsChange(Notification(name: .settingsDidChangeViaURI))
        #expect(visibility.tooltipDelay == before)
    }

    // MARK: Layout and the smaller pages

    @Test("Layout and the smaller pages write each change through to Defaults and load back")
    func layoutAndSmallPagesPersist() {
        let layout = LayoutSettings()
        layout.enableAlwaysHiddenSection = !Defaults.DefaultValue.enableAlwaysHiddenSection
        layout.showAllSectionsOnUserDrag = !Defaults.DefaultValue.showAllSectionsOnUserDrag
        layout.sectionDividerStyle = .slash
        layout.customSectionDividerImage = Data([9, 9])
        layout.customSectionDividerIsTemplate = !Defaults.DefaultValue.customSectionDividerIsTemplate
        layout.menuBarArrangementMode = .manual
        layout.iconRefreshInterval = 2
        layout.enableModuleStandIns = !Defaults.DefaultValue.enableModuleStandIns
        layout.skippedModuleStandIns = ["b", "a"]
        layout.enableTimeMachineTakeover = !Defaults.DefaultValue.enableTimeMachineTakeover
        layout.enableTimerTakeover = !Defaults.DefaultValue.enableTimerTakeover
        layout.enableTextInputTakeover = !Defaults.DefaultValue.enableTextInputTakeover
        layout.enableExperimentalOverflowPrevention = !Defaults.DefaultValue.enableExperimentalOverflowPrevention
        layout.alwaysUseAppIconForMenuBarItems = !Defaults.DefaultValue.alwaysUseAppIconForMenuBarItems
        layout.menuBarOrderFulfillmentTimeout = 9
        let privacy = PrivacySettings()
        privacy.fetchReleaseNotes = !Defaults.DefaultValue.fetchReleaseNotes
        privacy.showReleaseNotesAfterUpdate = !Defaults.DefaultValue.showReleaseNotesAfterUpdate
        let tools = ToolsSettings()
        tools.enableDiagnosticLogging = !Defaults.DefaultValue.enableDiagnosticLogging
        let widgets = WidgetsSettings()
        widgets.enableControlItemPanel = !Defaults.DefaultValue.enableControlItemPanel
        let spaces = SpacesSettings()
        spaces.showSpaceIndicator = !Defaults.DefaultValue.showSpaceIndicator

        #expect(Defaults.stringArray(forKey: .skippedModuleStandIns) == ["a", "b"])
        #expect(Defaults.data(forKey: .customSectionDividerImage) == Data([9, 9]))

        let reloadedLayout = LayoutSettings()
        reloadedLayout.loadInitialState()
        #expect(reloadedLayout.enableAlwaysHiddenSection == layout.enableAlwaysHiddenSection)
        #expect(reloadedLayout.isAlwaysHiddenSectionEnabled == layout.enableAlwaysHiddenSection)
        #expect(reloadedLayout.showAllSectionsOnUserDrag == layout.showAllSectionsOnUserDrag)
        #expect(reloadedLayout.sectionDividerStyle == .slash)
        #expect(reloadedLayout.customSectionDividerImage == Data([9, 9]))
        #expect(reloadedLayout.customSectionDividerIsTemplate == layout.customSectionDividerIsTemplate)
        #expect(reloadedLayout.menuBarArrangementMode == .manual)
        #expect(reloadedLayout.iconRefreshInterval == 2)
        #expect(reloadedLayout.enableModuleStandIns == layout.enableModuleStandIns)
        #expect(reloadedLayout.skippedModuleStandIns == ["a", "b"])
        #expect(reloadedLayout.enableTimeMachineTakeover == layout.enableTimeMachineTakeover)
        #expect(reloadedLayout.enableTimerTakeover == layout.enableTimerTakeover)
        #expect(reloadedLayout.enableTextInputTakeover == layout.enableTextInputTakeover)
        #expect(reloadedLayout.enableExperimentalOverflowPrevention == layout.enableExperimentalOverflowPrevention)
        #expect(reloadedLayout.alwaysUseAppIconForMenuBarItems == layout.alwaysUseAppIconForMenuBarItems)
        #expect(reloadedLayout.menuBarOrderFulfillmentTimeout == 9)

        let reloadedPrivacy = PrivacySettings()
        reloadedPrivacy.loadInitialState()
        #expect(reloadedPrivacy.fetchReleaseNotes == privacy.fetchReleaseNotes)
        #expect(reloadedPrivacy.showReleaseNotesAfterUpdate == privacy.showReleaseNotesAfterUpdate)
        let reloadedTools = ToolsSettings()
        reloadedTools.loadInitialState()
        #expect(reloadedTools.enableDiagnosticLogging == tools.enableDiagnosticLogging)
        let reloadedWidgets = WidgetsSettings()
        reloadedWidgets.loadInitialState()
        #expect(reloadedWidgets.enableControlItemPanel == widgets.enableControlItemPanel)
        let reloadedSpaces = SpacesSettings()
        reloadedSpaces.loadInitialState()
        #expect(reloadedSpaces.showSpaceIndicator == spaces.showSpaceIndicator)

        layout.customSectionDividerImage = nil
        #expect(Defaults.data(forKey: .customSectionDividerImage) == nil)
    }

    @Test("Native hiding and Apple-item hiding are opposites")
    func nativeHidingFlipsAppleItems() {
        let settings = LayoutSettings()
        settings.enableNativeAppHiding = false
        #expect(settings.enableExperimentalSystemItemHiding)
        settings.enableNativeAppHiding = true
        #expect(!settings.enableExperimentalSystemItemHiding)
        #expect(Defaults.bool(forKey: .enableNativeAppHiding))
    }

    @Test("Stored enum values that are not recognised leave the defaults")
    func pageModelsIgnoreGarbage() {
        Defaults.set("nowhere", forKey: .recordingWatchScreen)
        Defaults.set("nowhere", forKey: .recordingWatchPlacement)
        Defaults.set("nowhere", forKey: .menuBarSearchPresentation)
        Defaults.set(99, forKey: .sectionDividerStyle)
        Defaults.set(99, forKey: .menuBarArrangementMode)
        let visibility = VisibilitySettings()
        visibility.loadInitialState()
        let layout = LayoutSettings()
        layout.loadInitialState()
        #expect(visibility.recordingWatchScreen == Defaults.DefaultValue.recordingWatchScreen)
        #expect(visibility.recordingWatchPlacement == Defaults.DefaultValue.recordingWatchPlacement)
        #expect(visibility.menuBarSearchPresentation == Defaults.DefaultValue.menuBarSearchPresentation)
        #expect(layout.sectionDividerStyle == Defaults.DefaultValue.sectionDividerStyle)
        #expect(layout.menuBarArrangementMode == Defaults.DefaultValue.menuBarArrangementMode)
    }

    @Test("Layout and the smaller pages' URI changes set booleans and intervals by key")
    func layoutAndSmallPagesURIChanges() {
        let layout = LayoutSettings()
        let bools: [String: ReferenceWritableKeyPath<LayoutSettings, Bool>] = [
            "enableAlwaysHiddenSection": \.enableAlwaysHiddenSection,
            "showAllSectionsOnUserDrag": \.showAllSectionsOnUserDrag,
            "enableMenuBarItemOverflow": \.enableMenuBarItemOverflow,
            "enableExperimentalOverflowPrevention": \.enableExperimentalOverflowPrevention,
            "alwaysUseAppIconForMenuBarItems": \.alwaysUseAppIconForMenuBarItems,
        ]
        for (key, path) in bools {
            let flipped = !layout[keyPath: path]
            layout.handleExternalSettingsChange(uriChange(key, ["value": flipped]))
            #expect(layout[keyPath: path] == flipped, "\(key) follows the URI")
        }
        let doubles: [String: ReferenceWritableKeyPath<LayoutSettings, Double>] = [
            "iconRefreshInterval": \.iconRefreshInterval,
            "menuBarOrderFulfillmentTimeout": \.menuBarOrderFulfillmentTimeout,
        ]
        for (key, path) in doubles {
            layout.handleExternalSettingsChange(uriChange(key, ["doubleValue": 4.5]))
            #expect(layout[keyPath: path] == 4.5, "\(key) follows the URI")
        }

        let privacy = PrivacySettings()
        let fetch = !privacy.fetchReleaseNotes
        privacy.handleExternalSettingsChange(uriChange("fetchReleaseNotes", ["value": fetch]))
        #expect(privacy.fetchReleaseNotes == fetch)
        let show = !privacy.showReleaseNotesAfterUpdate
        privacy.handleExternalSettingsChange(uriChange("showReleaseNotesAfterUpdate", ["value": show]))
        #expect(privacy.showReleaseNotesAfterUpdate == show)

        let tools = ToolsSettings()
        let logging = !tools.enableDiagnosticLogging
        tools.handleExternalSettingsChange(uriChange("enableDiagnosticLogging", ["value": logging]))
        #expect(tools.enableDiagnosticLogging == logging)

        let widgets = WidgetsSettings()
        let panel = !widgets.enableControlItemPanel
        widgets.handleExternalSettingsChange(uriChange("enableControlItemPanel", ["value": panel]))
        #expect(widgets.enableControlItemPanel == panel)

        let spaces = SpacesSettings()
        let indicator = !spaces.showSpaceIndicator
        spaces.handleExternalSettingsChange(uriChange("showSpaceIndicator", ["value": indicator]))
        #expect(spaces.showSpaceIndicator == indicator)

        let before = layout.iconRefreshInterval
        layout.handleExternalSettingsChange(uriChange("unknown", ["value": true, "doubleValue": 8.0]))
        layout.handleExternalSettingsChange(Notification(name: .settingsDidChangeViaURI))
        #expect(layout.iconRefreshInterval == before)
    }

    /// Yields to the main actor until condition holds or a generous bound passes.
    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: Reset

    @Test("Resetting the page and Display settings puts back every default")
    func resetPagesAndDisplay() throws {
        try Defaults.set(JSONEncoder().encode([String: DisplayThawBarConfiguration]()), forKey: .displayThawBarConfigurations)
        let settings = AppSettings()
        settings.layout.enableAlwaysHiddenSection = !Defaults.DefaultValue.enableAlwaysHiddenSection
        settings.layout.sectionDividerStyle = .custom
        settings.layout.customSectionDividerImage = Data([1])
        settings.visibility.tooltipDelay = 9
        settings.layout.skippedModuleStandIns = ["x"]
        settings.visibility.menuBarSearchPresentation = .compact
        Defaults.set(false, forKey: .showSearchShortcutBar)
        settings.displaySettings.configurations = ["X": DisplayThawBarConfiguration.defaultConfiguration.withUseThawBar(true)]
        settings.displaySettings.globalConfiguration = DisplayThawBarConfiguration.defaultConfiguration.withGridColumns(8)
        settings.displaySettings.confirmSpacingRelaunch = !Defaults.DefaultValue.confirmSpacingRelaunch
        settings.displaySettings.wideDisplayRule.isEnabled = !Defaults.DefaultValue.showEveryItemOnWideDisplays

        settings.resetLayout()
        settings.resetVisibility()
        settings.resetDisplay()
        settings.resetAppearance()

        #expect(settings.layout.enableAlwaysHiddenSection == Defaults.DefaultValue.enableAlwaysHiddenSection)
        #expect(settings.layout.sectionDividerStyle == Defaults.DefaultValue.sectionDividerStyle)
        #expect(settings.layout.customSectionDividerImage == nil)
        #expect(settings.visibility.tooltipDelay == Defaults.DefaultValue.tooltipDelay)
        #expect(settings.layout.skippedModuleStandIns == Set(Defaults.DefaultValue.skippedModuleStandIns))
        #expect(settings.visibility.menuBarSearchPresentation == Defaults.DefaultValue.menuBarSearchPresentation)
        #expect(Defaults.bool(forKey: .showSearchShortcutBar) == Defaults.DefaultValue.showSearchShortcutBar)
        #expect(settings.displaySettings.configurations == Defaults.DefaultValue.displayThawBarConfigurations)
        #expect(settings.displaySettings.globalConfiguration == Defaults.DefaultValue.globalDisplayConfiguration)
        #expect(settings.displaySettings.confirmSpacingRelaunch == Defaults.DefaultValue.confirmSpacingRelaunch)
        #expect(settings.displaySettings.wideDisplayRule.isEnabled == Defaults.DefaultValue.showEveryItemOnWideDisplays)
    }

    @Test("Resetting hotkeys clears every binding and the stored dictionary")
    func resetHotkeys() {
        let settings = AppSettings()
        Defaults.set(["toggleHidden": Data([1])], forKey: .hotkeys)
        settings.resetHotkeys()
        #expect((Defaults.dictionary(forKey: .hotkeys) ?? [:]).isEmpty)
        #expect(settings.hotkeys.hotkeys.allSatisfy { $0.keyCombination == nil })
    }

    @Test("Reloading stored values picks up writes made by another process")
    func loadStoredValues() {
        let settings = AppSettings()
        Defaults.set(!settings.visibility.showOnScroll, forKey: .showOnScroll)
        Defaults.set(7.0, forKey: .tooltipDelay)
        let expected = !settings.visibility.showOnScroll
        settings.loadStoredValues()
        #expect(settings.visibility.showOnScroll == expected)
        #expect(settings.visibility.tooltipDelay == 7)
    }

    // MARK: Small enums

    @Test("Rehide strategies parse from names and raw values")
    func rehideStrategyParsing() {
        #expect(RehideStrategy.fromString("smart") == .smart)
        #expect(RehideStrategy.fromString("1") == .timed)
        #expect(RehideStrategy.fromString("focusedApp") == .focusedApp)
        #expect(RehideStrategy.fromString("focused_app") == .focusedApp)
        #expect(RehideStrategy.fromString("2") == .focusedApp)
        #expect(RehideStrategy.fromString("0") == .smart)
        #expect(RehideStrategy.fromString("timed") == .timed)
        #expect(RehideStrategy.fromString("never") == nil)
        #expect(RehideStrategy.allCases.map(\.id) == [0, 1, 2])
        for strategy in RehideStrategy.allCases {
            _ = strategy.localized
        }
    }

    @Test("Only automatic arrangement enforces order")
    func arrangementMode() {
        #expect(MenuBarArrangementMode.automatic.permitsOrderEnforcement)
        #expect(!MenuBarArrangementMode.manual.permitsOrderEnforcement)
        #expect(MenuBarArrangementMode.allCases.map(\.id) == [0, 1])
        for mode in MenuBarArrangementMode.allCases {
            _ = mode.localized
            _ = mode.explanation
        }
    }
}

/// Hotkey bindings wired to an AppState that is never started. Each test binds
/// an unusual combination only for as long as it takes to check the stored value.
@MainActor
@Suite("Hotkeys settings", .serialized, .scratchDefaults)
struct HotkeysSettingsTests {
    private static let combination = KeyCombination(key: KeyCode(rawValue: 0x6A), modifiers: [.command, .option, .control, .shift])

    @Test("A stored binding loads at setup, and changes write back or clear the key")
    func bindingRoundTrip() throws {
        let action = try #require(HotkeyAction.settingsActions.first)
        try Defaults.set([action.rawValue: JSONEncoder().encode(Self.combination)], forKey: .hotkeys)
        let appState = AppState()
        let settings = appState.settings.hotkeys
        settings.performSetup(with: appState)
        let hotkey = try #require(settings.hotkey(withAction: action))
        defer { hotkey.keyCombination = nil }

        #expect(hotkey.keyCombination == Self.combination)

        hotkey.keyCombination = nil
        let afterClear = Defaults.dictionary(forKey: .hotkeys) as? [String: Data] ?? [:]
        #expect(afterClear[action.rawValue] == nil)
        #expect(!hotkey.isEnabled)

        hotkey.keyCombination = Self.combination
        let afterSet = Defaults.dictionary(forKey: .hotkeys) as? [String: Data] ?? [:]
        let stored = try #require(afterSet[action.rawValue])
        #expect(try JSONDecoder().decode(KeyCombination.self, from: stored) == Self.combination)
        hotkey.keyCombination = nil
        #expect(settings.lastPersistenceError == nil)
        settings.clearPersistenceError()
    }

    @Test("A stored binding that cannot be decoded is skipped")
    func badStoredBinding() throws {
        let action = try #require(HotkeyAction.settingsActions.first)
        Defaults.set([action.rawValue: Data("x".utf8)], forKey: .hotkeys)
        let appState = AppState()
        appState.settings.hotkeys.performSetup(with: appState)
        #expect(appState.settings.hotkeys.hotkey(withAction: action)?.keyCombination == nil)
    }

    @Test("Every settings action has exactly one hotkey")
    func everyActionHasHotkey() {
        let settings = HotkeysSettings()
        for action in HotkeyAction.settingsActions {
            #expect(settings.hotkey(withAction: action)?.action == action)
        }
        #expect(settings.hotkeys.count == HotkeyAction.settingsActions.count)
    }
}
