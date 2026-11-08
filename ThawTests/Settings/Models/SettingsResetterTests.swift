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

    @Test("Reset brings back the welcome and What's New, asks TipKit to clear at the next launch, and keeps setup and update consent")
    func resetFirstRunState() throws {
        let defaults = try #require(suites.make())
        defaults.set(true, forKey: Defaults.Key.hasSeenOnboarding.rawValue)
        defaults.set(3, forKey: Defaults.Key.onboardingVersion.rawValue)
        defaults.set("3.0.0", forKey: Defaults.Key.lastWhatsNewVersion.rawValue)
        defaults.set(true, forKey: Defaults.Key.hasCompletedFirstLaunch.rawValue)
        defaults.set(true, forKey: Defaults.Key.hasSeenUpdateConsent.rawValue)

        AppSettings.resetFirstRunState(in: defaults)

        for key in AppSettings.firstRunKeys {
            #expect(defaults.object(forKey: key) == nil, "\(key) survived the reset")
        }
        #expect(defaults.bool(forKey: FeatureTips.resetAtNextLaunchKey))
        #expect(defaults.bool(forKey: Defaults.Key.hasCompletedFirstLaunch.rawValue), "setup does not run again")
        #expect(defaults.bool(forKey: Defaults.Key.hasSeenUpdateConsent.rawValue), "update consent is not asked again")
    }

    @Test("Reset turns thaw:// off and forgets every allowed app")
    func resetAllowedApps() {
        Defaults.set(["com.example.app"], forKey: .settingsURIWhitelist)
        Defaults.set(["com.example.app": "TEAM"], forKey: .settingsURISigningIdentities)
        Defaults.set(true, forKey: .settingsURIEnabled)
        let settings = AppSettings()
        settings.privacy.isSettingsURIEnabled = true

        settings.resetAllowedApps()

        #expect(!settings.privacy.isSettingsURIEnabled)
        #expect(!Defaults.bool(forKey: .settingsURIEnabled))
        #expect(Defaults.stringArray(forKey: .settingsURIWhitelist) == nil)
        #expect(Defaults.store.object(forKey: Defaults.Key.settingsURISigningIdentities.rawValue) == nil)
        #expect(settings.privacy.whitelistedApps.isEmpty)
    }

    @Test("Reset brings every first-run hint back")
    func resetHints() {
        var stored = [FirstRunHint.allCases.first.map(\.rawValue) ?? ""]
        let store = FirstRunHintStore(read: { stored }, write: { stored = $0 }, onFirstHide: {})
        #expect(!store.dismissed.isEmpty)
        store.reset()
        #expect(store.dismissed.isEmpty)
        #expect(stored.isEmpty)
    }

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
