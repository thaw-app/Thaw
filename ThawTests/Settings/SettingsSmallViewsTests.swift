//
//  SettingsSmallViewsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

/// Small Settings views, drawn off screen and measured, with settings in a throwaway suite.
@Suite("Small Settings views", .serialized)
@MainActor
final class SettingsSmallViewsTests {
    private let suites = ScratchSuites(prefix: "SettingsSmallViewsTests")
    private let previousStore = Defaults.store
    private let previousCenter = SettingsURIHandler.settingsChangeNotificationCenter

    init() throws {
        Defaults.store = try #require(suites.make())
        SettingsURIHandler.settingsChangeNotificationCenter = NotificationCenter()
    }

    isolated deinit {
        SettingsURIHandler.settingsChangeNotificationCenter = previousCenter
        Defaults.store = previousStore
    }

    /// The height the view asks for at a fixed width, after one layout pass.
    private func height(of view: some View) -> CGFloat {
        let host = NSHostingView(rootView: view.frame(width: 320))
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    @Test("A row's detail shows under the title unless descriptions are hidden")
    func rowLabelDetail() {
        let shown = height(of: ThawRowLabel("Title", detail: "A line of detail"))
        let hidden = height(of: ThawRowLabel("Title", detail: "A line of detail")
            .environment(\.settingsDescriptionsVisible, false))
        let verbatim = height(of: ThawRowLabel("Title", verbatimDetail: "build 114"))
        let titleOnly = height(of: ThawRowLabel("Title"))
        #expect(shown > hidden)
        #expect(verbatim > titleOnly)
        #expect(hidden == titleOnly)
    }

    @Test("Every switch What's New offers is off by default, and an older release offers them all")
    func offeredSwitches() {
        let settings = AdvancedSettings()
        let offered = WhatsNewSwitch.offered(release: "3.0.0-alpha.6", settings: settings)
        #expect(offered.first?.id == "controlItemPanel")
        #expect(Set(offered.map(\.id)) == Set(WhatsNewSwitch.all.map(\.id)))
    }

    @Test("A switch turned on is no longer offered by a later release")
    func switchTurnedOnIsDropped() {
        let settings = AdvancedSettings()
        settings.enableRecordingWatch = true
        let offered = WhatsNewSwitch.offered(release: "9.9.9", settings: settings).map(\.id)
        #expect(!offered.contains("recordingWatch"))
        #expect(offered.contains("desktopMenuHiding"))
    }

    @Test("What's New draws its switches while some are off, and nothing once all are on")
    func switchesView() {
        let settings = AdvancedSettings()
        let withSwitches = height(of: WhatsNewSwitchesView(settings: settings))
        for item in WhatsNewSwitch.all {
            settings[keyPath: item.keyPath] = true
        }
        let without = height(of: WhatsNewSwitchesView(settings: settings))
        #expect(withSwitches > without)
    }

    @Test("Every pane has a title and a subtitle")
    func paneTitles() {
        for pane in SettingsNavigationIdentifier.allCases {
            _ = pane.localized
            _ = pane.subtitle
        }
        #expect(SettingsNavigationIdentifier.displays.localized == "Displays & Spaces")
        #expect(SettingsNavigationIdentifier.automation.subtitle == "Triggers, other apps and scripts")
    }
}
