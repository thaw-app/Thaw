//
//  SettingsMissingRowsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@MainActor
@Suite("Settings that gained rows", .serialized, .scratchDefaults)
struct SettingsMissingRowsTests {
    @Test("Simple Mode names a way back that works")
    func simpleModeHelp() {
        #expect(SimpleModeHowItWorks.text(showsIcon: true, showsOnClick: true).contains("icon"))
        let noIcon = SimpleModeHowItWorks.text(showsIcon: false, showsOnClick: true)
        #expect(!noIcon.contains("icon to show"))
        #expect(noIcon.contains("empty part of the menu bar"))
        #expect(SimpleModeHowItWorks.text(showsIcon: false, showsOnClick: false).contains("shortcut"))
    }

    @Test("With the Dock icon off, a window you open only activates Thaw")
    func dockIconPolicy() {
        #expect(AppState.userWindowActivationPolicy(showDockIcon: true) == .regular)
        #expect(AppState.userWindowActivationPolicy(showDockIcon: false) == nil)
    }

    @Test("Thaw 2's stored Dock icon choice is read, and on when never set")
    func dockIconStoredValue() {
        #expect(AppState.storedShowDockIconWithSettings, "on by default, as Thaw 3 has behaved")
        Defaults.store.set(false, forKey: "ShowDockIconWithSettings")
        #expect(!AppState.storedShowDockIconWithSettings)
        let general = GeneralSettings()
        general.loadInitialState()
        #expect(!general.showDockIconWithSettings)
    }

    @Test("A chosen display that is disconnected stays listed, so the picker shows it")
    func disconnectedDisplayStaysListed() {
        let gone = RecordingWatchScreen.display(uuid: "GONE-DISPLAY")
        let choices = RecordingAlertRows.screenChoices(current: gone)
        #expect(choices.first?.choice == .screenWithPointer)
        #expect(choices.contains { $0.choice == gone })
        #expect(RecordingAlertRows.screenChoices(current: .mainDisplay).filter { $0.choice == .mainDisplay }.count == 1)
    }
}
