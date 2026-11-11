//
//  SettingsResetterTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw
import ThawUI

@MainActor
@Suite("Resetting every setting", .serialized, .scratchDefaults)
struct SettingsResetterTests {
    private let suites = ScratchSuites(prefix: "SettingsResetterTests")

    @Test("Resetting General puts back every default and forgets the UI zoom")
    func resetGeneral() throws {
        let zoom = try #require(suites.make())
        zoom.set(150, forKey: AppUIZoom.defaultsKey)
        let settings = AppSettings()
        let general = settings.general
        general.showThawIcon = !Defaults.DefaultValue.showThawIcon
        general.simpleMode = !Defaults.DefaultValue.simpleMode
        general.showSettingDescriptions = !Defaults.DefaultValue.showSettingDescriptions
        general.settingsAppearance = .black
        general.hideApplicationMenus = !Defaults.DefaultValue.hideApplicationMenus

        settings.resetGeneral(zoomDefaults: zoom)

        #expect(zoom.object(forKey: AppUIZoom.defaultsKey) == nil)
        #expect(general.showThawIcon == Defaults.DefaultValue.showThawIcon)
        #expect(general.simpleMode == Defaults.DefaultValue.simpleMode)
        #expect(general.showSettingDescriptions == Defaults.DefaultValue.showSettingDescriptions)
        #expect(general.settingsAppearance == .system)
        #expect(general.hideApplicationMenus == Defaults.DefaultValue.hideApplicationMenus)
        #expect(general.lastCustomThawIcon == nil)
    }

    @Test("Resetting Visibility, Thaw Bar and screen corners puts back their defaults")
    func resetVisibilityThawBarAndCorners() {
        let settings = AppSettings()
        settings.thawBar.lockThawBarPosition = !Defaults.DefaultValue.lockThawBarPosition
        settings.appearance.screenCornerRadius = Defaults.DefaultValue.screenCornerRadius + 3
        settings.visibility.showOnHover = !Defaults.DefaultValue.showOnHover
        settings.visibility.autoRehide = !Defaults.DefaultValue.autoRehide
        settings.visibility.rehideStrategy = Defaults.DefaultValue.rehideStrategy == .timed ? .smart : .timed
        settings.visibility.rehideInterval = Defaults.DefaultValue.rehideInterval + 7

        settings.resetVisibility()
        settings.resetThawBar()
        settings.resetScreenCorners()

        #expect(settings.thawBar.lockThawBarPosition == Defaults.DefaultValue.lockThawBarPosition)
        #expect(settings.appearance.screenCornerRadius == Defaults.DefaultValue.screenCornerRadius)
        #expect(settings.visibility.showOnHover == Defaults.DefaultValue.showOnHover)
        #expect(settings.visibility.autoRehide == Defaults.DefaultValue.autoRehide)
        #expect(settings.visibility.rehideStrategy == Defaults.DefaultValue.rehideStrategy)
        #expect(settings.visibility.rehideInterval == Defaults.DefaultValue.rehideInterval)
    }

    @Test("Resetting everything reaches every page, Hotkeys and Display together")
    func resetAll() throws {
        let zoom = try #require(suites.make())
        zoom.set(80, forKey: AppUIZoom.defaultsKey)
        Defaults.set(["toggleHidden": Data([1])], forKey: .hotkeys)
        let settings = AppSettings()
        settings.visibility.showOnHover = !Defaults.DefaultValue.showOnHover
        settings.visibility.tooltipDelay = 9
        settings.privacy.showReleaseNotesAfterUpdate = !Defaults.DefaultValue.showReleaseNotesAfterUpdate
        settings.displaySettings.confirmSpacingRelaunch = !Defaults.DefaultValue.confirmSpacingRelaunch

        settings.resetAllSettingsToDefaults(zoomDefaults: zoom)

        #expect(zoom.object(forKey: AppUIZoom.defaultsKey) == nil)
        #expect(settings.visibility.showOnHover == Defaults.DefaultValue.showOnHover)
        #expect(settings.visibility.tooltipDelay == Defaults.DefaultValue.tooltipDelay)
        #expect(settings.privacy.showReleaseNotesAfterUpdate == Defaults.DefaultValue.showReleaseNotesAfterUpdate)
        #expect(settings.displaySettings.confirmSpacingRelaunch == Defaults.DefaultValue.confirmSpacingRelaunch)
        #expect((Defaults.dictionary(forKey: .hotkeys) ?? [:]).isEmpty)
    }
}
