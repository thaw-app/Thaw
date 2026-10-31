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
        general.lockThawBarPosition = !Defaults.DefaultValue.lockThawBarPosition
        general.screenCornerRadius = Defaults.DefaultValue.screenCornerRadius + 3
        general.showOnHover = !Defaults.DefaultValue.showOnHover
        general.autoRehide = !Defaults.DefaultValue.autoRehide
        general.rehideStrategy = Defaults.DefaultValue.rehideStrategy == .timed ? .smart : .timed
        general.rehideInterval = Defaults.DefaultValue.rehideInterval + 7

        settings.resetGeneral(zoomDefaults: zoom)

        #expect(zoom.object(forKey: AppUIZoom.defaultsKey) == nil)
        #expect(general.showThawIcon == Defaults.DefaultValue.showThawIcon)
        #expect(general.simpleMode == Defaults.DefaultValue.simpleMode)
        #expect(general.showSettingDescriptions == Defaults.DefaultValue.showSettingDescriptions)
        #expect(general.lockThawBarPosition == Defaults.DefaultValue.lockThawBarPosition)
        #expect(general.screenCornerRadius == Defaults.DefaultValue.screenCornerRadius)
        #expect(general.showOnHover == Defaults.DefaultValue.showOnHover)
        #expect(general.autoRehide == Defaults.DefaultValue.autoRehide)
        #expect(general.rehideStrategy == Defaults.DefaultValue.rehideStrategy)
        #expect(general.rehideInterval == Defaults.DefaultValue.rehideInterval)
        #expect(general.lastCustomThawIcon == nil)
    }

    @Test("Resetting everything reaches General, Advanced, Hotkeys and Display together")
    func resetAll() throws {
        let zoom = try #require(suites.make())
        zoom.set(80, forKey: AppUIZoom.defaultsKey)
        Defaults.set(["toggleHidden": Data([1])], forKey: .hotkeys)
        let settings = AppSettings()
        settings.general.showOnHover = !Defaults.DefaultValue.showOnHover
        settings.advanced.tooltipDelay = 9
        settings.displaySettings.confirmSpacingRelaunch = !Defaults.DefaultValue.confirmSpacingRelaunch

        settings.resetAllSettingsToDefaults(zoomDefaults: zoom)

        #expect(zoom.object(forKey: AppUIZoom.defaultsKey) == nil)
        #expect(settings.general.showOnHover == Defaults.DefaultValue.showOnHover)
        #expect(settings.advanced.tooltipDelay == Defaults.DefaultValue.tooltipDelay)
        #expect(settings.displaySettings.confirmSpacingRelaunch == Defaults.DefaultValue.confirmSpacingRelaunch)
        #expect((Defaults.dictionary(forKey: .hotkeys) ?? [:]).isEmpty)
    }
}
