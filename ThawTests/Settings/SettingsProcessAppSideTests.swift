//
//  SettingsProcessAppSideTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import Testing
@testable import Thaw

/// What the app does for its settings process, with settings in a throwaway suite.
@Suite("Settings process, app side", .serialized)
@MainActor
final class SettingsProcessAppSideTests {
    private let suites = ScratchSuites(prefix: "SettingsProcessAppSideTests")
    private let previousStore = Defaults.store

    init() throws {
        Defaults.store = try #require(suites.make())
    }

    isolated deinit {
        Defaults.store = previousStore
    }

    @Test("Only Settings goes to the process, never while it is open here or the setting is off")
    func showsInSettingsProcess() {
        let appState = AppState()
        #expect(!appState.showsInSettingsProcess(.permissions, isOpenHere: false))
        #expect(!appState.showsInSettingsProcess(.settings, isOpenHere: true))
        #expect(!appState.showsInSettingsProcess(.settings, isOpenHere: false), "The setting is off in a fresh suite")
    }

    @Test("A page change from the process moves the app's pane, and an unknown pane is ignored")
    func pageChanged() {
        let appState = AppState()
        let side = appState.settingsProcessAppSide()
        side.pageChanged("Privacy")
        #expect(appState.navigationState.settingsNavigationIdentifier == .privacy)
        side.pageChanged("Nowhere")
        #expect(appState.navigationState.settingsNavigationIdentifier == .privacy)
    }

    @Test("The updater state sent to the process is the app's own")
    func updatesState() {
        let appState = AppState()
        let side = appState.settingsProcessAppSide()
        let checked = Date(timeIntervalSince1970: 1_800_000_000)
        appState.updatesManager.canCheckForUpdates = true
        appState.updatesManager.lastUpdateCheckDate = checked
        #expect(side.updatesState() == .updatesState(canCheck: true, lastCheck: checked))
    }

    @Test("Settings written by the process are read again")
    func reloadSettings() {
        let appState = AppState()
        let side = appState.settingsProcessAppSide()
        Defaults.set(true, forKey: .enableRecordingWatch)
        side.reloadSettings()
        #expect(appState.settings.advanced.enableRecordingWatch)
    }

    @Test("The host reads the setting from the defaults")
    func hostEnabledByDefaults() {
        #expect(!SettingsProcessHost.isEnabledInDefaults())
        Defaults.set(true, forKey: .settingsInOwnProcess)
        #expect(SettingsProcessHost.isEnabledInDefaults() == !SettingsProcessApp.isRequested)
    }
}

@Suite("Settings link endpoint")
@MainActor
struct SettingsLinkEndpointTests {
    @Test("Settings read while reloading are not sent back, and later writes are")
    func reloadingIsQuiet() async {
        let pipe = Pipe()
        let unused = Pipe()
        var received = [SettingsLinkMessage]()
        let reader = SettingsLinkEndpoint(input: pipe.fileHandleForReading, output: unused.fileHandleForWriting) {
            received.append($0)
        }
        let writer = SettingsLinkEndpoint(input: unused.fileHandleForReading, output: pipe.fileHandleForWriting) { _ in }
        var ran = false
        writer.reloading { ran = true }
        #expect(ran)
        writer.send(.checkForUpdates)
        #expect(await settingsLinkWait { received.contains(.checkForUpdates) })
        reader.close()
        writer.close()
    }

    @Test("A write after the other end has gone stops the link instead of killing the process")
    func writeToClosedPipe() throws {
        let pipe = Pipe()
        let input = Pipe()
        let endpoint = SettingsLinkEndpoint(input: input.fileHandleForReading, output: pipe.fileHandleForWriting) { _ in }
        try pipe.fileHandleForReading.close()
        endpoint.send(.quit)
        endpoint.send(.quit)
        endpoint.close()
    }

    @Test("Renaming the process to its own name succeeds")
    func processDisplayName() throws {
        let name = try #require(NSRunningApplication.current.localizedName)
        #expect(ProcessDisplayName.set(name))
    }
}
