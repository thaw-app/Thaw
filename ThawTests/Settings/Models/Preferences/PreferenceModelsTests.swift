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

/// The General and Advanced settings models on their own, with settings in a
/// throwaway suite. None is wired to an AppState, so no change reaches the menu bar.
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
        settings.blackSettingsBackground = !Defaults.DefaultValue.blackSettingsBackground
        settings.simpleModeShowsPreview = !Defaults.DefaultValue.simpleModeShowsPreview
        settings.lockThawBarPosition = !Defaults.DefaultValue.lockThawBarPosition
        settings.roundScreenCorners = !Defaults.DefaultValue.roundScreenCorners
        settings.screenCornerRadius = 22
        settings.openHiddenItemsInMenuBar = !Defaults.DefaultValue.openHiddenItemsInMenuBar
        settings.useThawBar = !Defaults.DefaultValue.useThawBar
        settings.useThawBarOnlyOnNotchedDisplay = !Defaults.DefaultValue.useThawBarOnlyOnNotchedDisplay
        settings.thawBarLocation = .leftAligned
        settings.thawBarLocationOnHotkey = !Defaults.DefaultValue.thawBarLocationOnHotkey
        settings.showOnClick = !Defaults.DefaultValue.showOnClick
        settings.showOnHover = !Defaults.DefaultValue.showOnHover
        settings.showOnScroll = !Defaults.DefaultValue.showOnScroll
        settings.autoRehide = !Defaults.DefaultValue.autoRehide
        settings.rehideStrategy = .focusedApp
        settings.rehideInterval = 42
        settings.tempShowInterval = 7

        #expect(Defaults.bool(forKey: .showThawIcon) == false)
        #expect(Defaults.double(forKey: .screenCornerRadius) == 22)
        #expect(Defaults.integer(forKey: .thawBarLocation) == ThawBarLocation.leftAligned.rawValue)
        #expect(Defaults.integer(forKey: .rehideStrategy) == RehideStrategy.focusedApp.rawValue)
        #expect(Defaults.double(forKey: .rehideInterval) == 42)
        #expect(Defaults.double(forKey: .tempShowInterval) == 7)

        let reloaded = GeneralSettings()
        reloaded.loadInitialState()
        #expect(reloaded.showThawIcon == false)
        #expect(reloaded.customThawIconIsTemplate == settings.customThawIconIsTemplate)
        #expect(reloaded.simpleMode == settings.simpleMode)
        #expect(reloaded.showSettingDescriptions == settings.showSettingDescriptions)
        #expect(reloaded.blackSettingsBackground == settings.blackSettingsBackground)
        #expect(reloaded.simpleModeShowsPreview == settings.simpleModeShowsPreview)
        #expect(reloaded.lockThawBarPosition == settings.lockThawBarPosition)
        #expect(reloaded.roundScreenCorners == settings.roundScreenCorners)
        #expect(reloaded.screenCornerRadius == 22)
        #expect(reloaded.openHiddenItemsInMenuBar == settings.openHiddenItemsInMenuBar)
        #expect(reloaded.useThawBar == settings.useThawBar)
        #expect(reloaded.useThawBarOnlyOnNotchedDisplay == settings.useThawBarOnlyOnNotchedDisplay)
        #expect(reloaded.thawBarLocation == .leftAligned)
        #expect(reloaded.thawBarLocationOnHotkey == settings.thawBarLocationOnHotkey)
        #expect(reloaded.showOnClick == settings.showOnClick)
        #expect(reloaded.showOnHover == settings.showOnHover)
        #expect(reloaded.showOnScroll == settings.showOnScroll)
        #expect(reloaded.autoRehide == settings.autoRehide)
        #expect(reloaded.rehideStrategy == .focusedApp)
        #expect(reloaded.rehideInterval == 42)
        #expect(reloaded.tempShowInterval == 7)
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
        let settings = GeneralSettings()
        settings.loadInitialState()
        #expect(settings.thawIcon == Defaults.DefaultValue.thawIcon)
        #expect(settings.thawBarLocation == Defaults.DefaultValue.thawBarLocation)
        #expect(settings.rehideStrategy == Defaults.DefaultValue.rehideStrategy)
    }

    @Test("General URI changes set the matching property and ignore everything else")
    func generalURIChanges() async {
        let appState = AppState()
        let settings = GeneralSettings()
        settings.performSetup(with: appState)
        let paths: [String: ReferenceWritableKeyPath<GeneralSettings, Bool>] = [
            "showThawIcon": \.showThawIcon, "customThawIconIsTemplate": \.customThawIconIsTemplate,
            "simpleMode": \.simpleMode, "showSettingDescriptions": \.showSettingDescriptions,
            "blackSettingsBackground": \.blackSettingsBackground,
            "lockThawBarPosition": \.lockThawBarPosition, "openHiddenItemsInMenuBar": \.openHiddenItemsInMenuBar,
            "useThawBarOnlyOnNotchedDisplay": \.useThawBarOnlyOnNotchedDisplay,
            "thawBarLocationOnHotkey": \.thawBarLocationOnHotkey, "showOnClick": \.showOnClick,
            "showOnHover": \.showOnHover, "showOnScroll": \.showOnScroll, "autoRehide": \.autoRehide,
        ]
        for (key, path) in paths {
            let flipped = !settings[keyPath: path]
            NotificationCenter.default.post(uriChange(key, ["value": flipped]))
            await waitUntil { settings[keyPath: path] == flipped }
            #expect(settings[keyPath: path] == flipped, "\(key) follows the URI")
        }

        NotificationCenter.default.post(uriChange("rehideInterval", ["doubleValue": 99.0]))
        NotificationCenter.default.post(uriChange("tempShowInterval", ["doubleValue": 3.0]))
        NotificationCenter.default.post(uriChange("rehideStrategy", ["rawEnumValue": RehideStrategy.timed.rawValue]))
        await waitUntil { settings.rehideStrategy == .timed }
        #expect(settings.rehideInterval == 99)
        #expect(settings.tempShowInterval == 3)
        #expect(settings.rehideStrategy == .timed)

        NotificationCenter.default.post(uriChange("rehideStrategy", ["rawEnumValue": 42]))
        NotificationCenter.default.post(uriChange("unknown", ["value": true, "doubleValue": 1.0]))
        NotificationCenter.default.post(Notification(name: .settingsDidChangeViaURI, userInfo: ["value": true]))
        NotificationCenter.default.post(uriChange("tempShowInterval", ["doubleValue": 4.0]))
        await waitUntil { settings.tempShowInterval == 4 }
        #expect(settings.rehideStrategy == .timed, "an unknown raw value changes nothing")
        #expect(settings.rehideInterval == 99)
    }

    // MARK: Advanced

    @Test("Advanced settings write each change through to Defaults and load back")
    func advancedPersists() {
        let settings = AdvancedSettings()
        settings.enableAlwaysHiddenSection = !Defaults.DefaultValue.enableAlwaysHiddenSection
        settings.showAllSectionsOnUserDrag = !Defaults.DefaultValue.showAllSectionsOnUserDrag
        settings.sectionDividerStyle = .slash
        settings.customSectionDividerImage = Data([9, 9])
        settings.customSectionDividerIsTemplate = !Defaults.DefaultValue.customSectionDividerIsTemplate
        settings.menuBarArrangementMode = .manual
        settings.hideApplicationMenus = !Defaults.DefaultValue.hideApplicationMenus
        settings.enableSecondaryContextMenu = !Defaults.DefaultValue.enableSecondaryContextMenu
        settings.showOnHoverDelay = 0.9
        settings.tooltipDelay = 1.1
        settings.showMenuBarTooltips = !Defaults.DefaultValue.showMenuBarTooltips
        settings.iconRefreshInterval = 2
        settings.autoZenWhileSharingScreen = !Defaults.DefaultValue.autoZenWhileSharingScreen
        settings.enableMenuBarItemDescenders = !Defaults.DefaultValue.enableMenuBarItemDescenders
        settings.enableSwapBar = !Defaults.DefaultValue.enableSwapBar
        settings.swapOnThawIconClick = !Defaults.DefaultValue.swapOnThawIconClick
        settings.enableControlItemPanel = !Defaults.DefaultValue.enableControlItemPanel
        settings.fetchReleaseNotes = !Defaults.DefaultValue.fetchReleaseNotes
        settings.enableModuleStandIns = !Defaults.DefaultValue.enableModuleStandIns
        settings.skippedModuleStandIns = ["b", "a"]
        settings.enableTimeMachineTakeover = !Defaults.DefaultValue.enableTimeMachineTakeover
        settings.enableTimerTakeover = !Defaults.DefaultValue.enableTimerTakeover
        settings.enableTextInputTakeover = !Defaults.DefaultValue.enableTextInputTakeover
        settings.enableRecordingWatch = !Defaults.DefaultValue.enableRecordingWatch
        settings.zenModeWhileRecording = !Defaults.DefaultValue.zenModeWhileRecording
        settings.recordingWatchScreen = .mainDisplay
        settings.recordingWatchPlacement = .leading
        settings.enableDesktopMenuHiding = !Defaults.DefaultValue.enableDesktopMenuHiding
        settings.enableExperimentalOverflowPrevention = !Defaults.DefaultValue.enableExperimentalOverflowPrevention
        settings.alwaysUseAppIconForMenuBarItems = !Defaults.DefaultValue.alwaysUseAppIconForMenuBarItems
        settings.menuBarOrderFulfillmentTimeout = 9
        settings.menuBarSearchPresentation = .launcher

        #expect(Defaults.stringArray(forKey: .skippedModuleStandIns) == ["a", "b"])
        #expect(Defaults.string(forKey: .recordingWatchScreen) == "mainDisplay")
        #expect(Defaults.data(forKey: .customSectionDividerImage) == Data([9, 9]))

        let reloaded = AdvancedSettings()
        reloaded.loadInitialState()
        #expect(reloaded.enableAlwaysHiddenSection == settings.enableAlwaysHiddenSection)
        #expect(reloaded.isAlwaysHiddenSectionEnabled == settings.enableAlwaysHiddenSection)
        #expect(reloaded.showAllSectionsOnUserDrag == settings.showAllSectionsOnUserDrag)
        #expect(reloaded.sectionDividerStyle == .slash)
        #expect(reloaded.customSectionDividerImage == Data([9, 9]))
        #expect(reloaded.customSectionDividerIsTemplate == settings.customSectionDividerIsTemplate)
        #expect(reloaded.menuBarArrangementMode == .manual)
        #expect(reloaded.hideApplicationMenus == settings.hideApplicationMenus)
        #expect(reloaded.enableSecondaryContextMenu == settings.enableSecondaryContextMenu)
        #expect(reloaded.showOnHoverDelay == 0.9)
        #expect(reloaded.tooltipDelay == 1.1)
        #expect(reloaded.showMenuBarTooltips == settings.showMenuBarTooltips)
        #expect(reloaded.iconRefreshInterval == 2)
        #expect(reloaded.autoZenWhileSharingScreen == settings.autoZenWhileSharingScreen)
        #expect(reloaded.enableMenuBarItemDescenders == settings.enableMenuBarItemDescenders)
        #expect(reloaded.enableSwapBar == settings.enableSwapBar)
        #expect(reloaded.swapOnThawIconClick == settings.swapOnThawIconClick)
        #expect(reloaded.enableControlItemPanel == settings.enableControlItemPanel)
        #expect(reloaded.fetchReleaseNotes == settings.fetchReleaseNotes)
        #expect(reloaded.enableModuleStandIns == settings.enableModuleStandIns)
        #expect(reloaded.skippedModuleStandIns == ["a", "b"])
        #expect(reloaded.enableTimeMachineTakeover == settings.enableTimeMachineTakeover)
        #expect(reloaded.enableTimerTakeover == settings.enableTimerTakeover)
        #expect(reloaded.enableTextInputTakeover == settings.enableTextInputTakeover)
        #expect(reloaded.enableRecordingWatch == settings.enableRecordingWatch)
        #expect(reloaded.zenModeWhileRecording == settings.zenModeWhileRecording)
        #expect(reloaded.recordingWatchScreen == .mainDisplay)
        #expect(reloaded.recordingWatchPlacement == .leading)
        #expect(reloaded.enableDesktopMenuHiding == settings.enableDesktopMenuHiding)
        #expect(reloaded.enableExperimentalOverflowPrevention == settings.enableExperimentalOverflowPrevention)
        #expect(reloaded.alwaysUseAppIconForMenuBarItems == settings.alwaysUseAppIconForMenuBarItems)
        #expect(reloaded.menuBarOrderFulfillmentTimeout == 9)
        #expect(reloaded.menuBarSearchPresentation == .launcher)

        settings.customSectionDividerImage = nil
        #expect(Defaults.data(forKey: .customSectionDividerImage) == nil)
    }

    @Test("Native hiding and Apple-item hiding are opposites")
    func nativeHidingFlipsAppleItems() {
        let settings = AdvancedSettings()
        settings.enableNativeAppHiding = false
        #expect(settings.enableExperimentalSystemItemHiding)
        settings.enableNativeAppHiding = true
        #expect(!settings.enableExperimentalSystemItemHiding)
        #expect(Defaults.bool(forKey: .enableNativeAppHiding))
    }

    @Test("Stored enum values that are not recognised leave the defaults")
    func advancedIgnoresGarbage() {
        Defaults.set("nowhere", forKey: .recordingWatchScreen)
        Defaults.set("nowhere", forKey: .recordingWatchPlacement)
        Defaults.set("nowhere", forKey: .menuBarSearchPresentation)
        Defaults.set(99, forKey: .sectionDividerStyle)
        Defaults.set(99, forKey: .menuBarArrangementMode)
        let settings = AdvancedSettings()
        settings.loadInitialState()
        #expect(settings.recordingWatchScreen == Defaults.DefaultValue.recordingWatchScreen)
        #expect(settings.recordingWatchPlacement == Defaults.DefaultValue.recordingWatchPlacement)
        #expect(settings.menuBarSearchPresentation == Defaults.DefaultValue.menuBarSearchPresentation)
        #expect(settings.sectionDividerStyle == Defaults.DefaultValue.sectionDividerStyle)
        #expect(settings.menuBarArrangementMode == Defaults.DefaultValue.menuBarArrangementMode)
    }

    @Test("Advanced URI changes set booleans and intervals by key")
    func advancedURIChanges() {
        let settings = AdvancedSettings()
        let paths: [String: ReferenceWritableKeyPath<AdvancedSettings, Bool>] = [
            "enableAlwaysHiddenSection": \.enableAlwaysHiddenSection,
            "showAllSectionsOnUserDrag": \.showAllSectionsOnUserDrag,
            "hideApplicationMenus": \.hideApplicationMenus,
            "enableSecondaryContextMenu": \.enableSecondaryContextMenu,
            "showMenuBarTooltips": \.showMenuBarTooltips,
            "autoZenWhileSharingScreen": \.autoZenWhileSharingScreen,
            "enableDiagnosticLogging": \.enableDiagnosticLogging,
            "enableMenuBarItemOverflow": \.enableMenuBarItemOverflow,
            "enableExperimentalOverflowPrevention": \.enableExperimentalOverflowPrevention,
            "alwaysUseAppIconForMenuBarItems": \.alwaysUseAppIconForMenuBarItems,
            "enableMenuBarItemDescenders": \.enableMenuBarItemDescenders,
            "enableSwapBar": \.enableSwapBar,
            "swapOnThawIconClick": \.swapOnThawIconClick,
            "enableControlItemPanel": \.enableControlItemPanel,
            "fetchReleaseNotes": \.fetchReleaseNotes,
            "enableRecordingWatch": \.enableRecordingWatch,
            "zenModeWhileRecording": \.zenModeWhileRecording,
            "enableDesktopMenuHiding": \.enableDesktopMenuHiding,
        ]
        for (key, path) in paths {
            let flipped = !settings[keyPath: path]
            settings.handleExternalSettingsChange(uriChange(key, ["value": flipped]))
            #expect(settings[keyPath: path] == flipped, "\(key) follows the URI")
        }
        let doubles: [String: ReferenceWritableKeyPath<AdvancedSettings, Double>] = [
            "showOnHoverDelay": \.showOnHoverDelay,
            "tooltipDelay": \.tooltipDelay,
            "iconRefreshInterval": \.iconRefreshInterval,
            "menuBarOrderFulfillmentTimeout": \.menuBarOrderFulfillmentTimeout,
        ]
        for (key, path) in doubles {
            settings.handleExternalSettingsChange(uriChange(key, ["doubleValue": 4.5]))
            #expect(settings[keyPath: path] == 4.5, "\(key) follows the URI")
        }
        let before = settings.tooltipDelay
        settings.handleExternalSettingsChange(uriChange("unknown", ["value": true, "doubleValue": 8.0]))
        settings.handleExternalSettingsChange(Notification(name: .settingsDidChangeViaURI))
        #expect(settings.tooltipDelay == before)
    }

    /// Yields to the main actor until condition holds or a generous bound passes.
    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: Reset

    @Test("Resetting Advanced and Display settings puts back every default")
    func resetAdvancedAndDisplay() throws {
        try Defaults.set(JSONEncoder().encode([String: DisplayThawBarConfiguration]()), forKey: .displayThawBarConfigurations)
        let settings = AppSettings()
        settings.advanced.enableAlwaysHiddenSection = !Defaults.DefaultValue.enableAlwaysHiddenSection
        settings.advanced.sectionDividerStyle = .custom
        settings.advanced.customSectionDividerImage = Data([1])
        settings.advanced.tooltipDelay = 9
        settings.advanced.skippedModuleStandIns = ["x"]
        settings.advanced.menuBarSearchPresentation = .assisted
        settings.displaySettings.configurations = ["X": DisplayThawBarConfiguration.defaultConfiguration.withUseThawBar(true)]
        settings.displaySettings.globalConfiguration = DisplayThawBarConfiguration.defaultConfiguration.withGridColumns(8)
        settings.displaySettings.confirmSpacingRelaunch = !Defaults.DefaultValue.confirmSpacingRelaunch
        settings.displaySettings.wideDisplayRule.isEnabled = !Defaults.DefaultValue.showEveryItemOnWideDisplays

        settings.resetAdvanced()
        settings.resetDisplay()
        settings.resetAppearance()

        #expect(settings.advanced.enableAlwaysHiddenSection == Defaults.DefaultValue.enableAlwaysHiddenSection)
        #expect(settings.advanced.sectionDividerStyle == Defaults.DefaultValue.sectionDividerStyle)
        #expect(settings.advanced.customSectionDividerImage == nil)
        #expect(settings.advanced.tooltipDelay == Defaults.DefaultValue.tooltipDelay)
        #expect(settings.advanced.skippedModuleStandIns == Set(Defaults.DefaultValue.skippedModuleStandIns))
        #expect(settings.advanced.menuBarSearchPresentation == Defaults.DefaultValue.menuBarSearchPresentation)
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
        Defaults.set(!settings.general.showOnScroll, forKey: .showOnScroll)
        Defaults.set(7.0, forKey: .tooltipDelay)
        let expected = !settings.general.showOnScroll
        settings.loadStoredValues()
        #expect(settings.general.showOnScroll == expected)
        #expect(settings.advanced.tooltipDelay == 7)
    }

    // MARK: Small enums

    @Test("Rehide strategies parse from names and raw values")
    func rehideStrategyParsing() {
        #expect(RehideStrategy.fromString("smart") == .smart)
        #expect(RehideStrategy.fromString("1") == .timed)
        #expect(RehideStrategy.fromString("focusedApp") == .focusedApp)
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
