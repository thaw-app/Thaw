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
@Suite("Settings process, app side", .serialized, .scratchDefaults)
@MainActor
final class SettingsProcessAppSideTests {
    @Test("Only Settings and its own windows go to the process, never while open here or with the setting off")
    func showsInSettingsProcess() {
        let appState = AppState()
        #expect(!appState.showsInSettingsProcess(.acknowledgements, isOpenHere: false), "only the app has it")
        #expect(!appState.showsInSettingsProcess(.settings, isOpenHere: true))
        // Off here, since a yes would start a real settings process.
        Defaults.set(false, forKey: .settingsInOwnProcess)
        #expect(!appState.showsInSettingsProcess(.settings, isOpenHere: false), "The setting is turned off")
    }

    @Test("What's New goes to the process like Settings, never while the app's own is open or the setting is off")
    func whatsNewInSettingsProcess() {
        let appState = AppState()
        #expect(!appState.showsInSettingsProcess(.whatsNew, isOpenHere: true))
        Defaults.set(false, forKey: .settingsInOwnProcess)
        #expect(!appState.showsInSettingsProcess(.whatsNew, isOpenHere: false))
        #expect(SettingsProcessRoute.runsInOwnProcess(pane: SettingsProcessRoute.whatsNew, simpleMode: true, isEnabled: true))
        #expect(!SettingsProcessRoute.runsInOwnProcess(pane: SettingsProcessRoute.whatsNew, simpleMode: false, isEnabled: false))
    }

    @Test("The welcome and the access screen go to the process like What's New, in Simple Mode too")
    func permissionsInSettingsProcess() {
        for target in [SettingsProcessRoute.permissions, SettingsProcessRoute.welcomeAgain] {
            #expect(SettingsProcessRoute.runsInOwnProcess(pane: target, simpleMode: true, isEnabled: true))
            #expect(!SettingsProcessRoute.runsInOwnProcess(pane: target, simpleMode: false, isEnabled: false))
        }
        let appState = AppState()
        #expect(!appState.showsInSettingsProcess(.permissions, isOpenHere: true))
    }

    @Test("Finishing the welcome in the app answers whether the window closes, and the process never launches")
    func finishAnswersAndProcessNeverLaunches() throws {
        let appState = AppState()
        let feature = OnboardingLink.app(appState)
        let finish = try #require(feature.requests[OnboardingLink.finish])
        #expect(finish != nil)
        // The app's answer follows the access it has and the Reduced mode choice.
        ReducedModeController.isChosen = true
        let answer = appState.completeFinish(OnboardingLink.Finish())
        #expect(answer.closesWindow)
        ReducedModeController.isChosen = false
        // A launch in the settings process does nothing; only the app runs the menu bar.
        #expect(!SettingsProcessApp.isRequested, "tests run as the app")
    }

    @Test("The process showing the handed-back page closes the app's Settings window once")
    func handBackFinishesOnPageChange() {
        let appState = AppState()
        let side = appState.settingsProcessAppSide()
        appState.settingsProcessHost.handBack.isPending = true
        side.pageChanged("General")
        #expect(!appState.settingsProcessHost.handBack.isPending)
        #expect(appState.navigationState.settingsNavigationIdentifier == .general)
        side.pageChanged("About")
        #expect(appState.navigationState.settingsNavigationIdentifier == .about, "a later page change is only a page change")
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
        #expect(appState.settings.visibility.enableRecordingWatch)
    }

    @Test("The host reads the setting from the defaults")
    func hostEnabledByDefaults() {
        #expect(SettingsProcessHost.isEnabledInDefaults(environment: [:]) == !SettingsProcessApp.isRequested, "on in a fresh suite")
        #expect(!SettingsProcessHost.isEnabledInDefaults(), "never in a unit-test run, which would start real processes")
        Defaults.set(false, forKey: .settingsInOwnProcess)
        #expect(!SettingsProcessHost.isEnabledInDefaults(environment: [:]))
        #expect(SettingsProcessHost.isEnabled(settingOn: true, isSettingsProcess: false, isTestHost: false))
        #expect(!SettingsProcessHost.isEnabled(settingOn: true, isSettingsProcess: true, isTestHost: false))
        #expect(!SettingsProcessHost.isEnabled(settingOn: true, isSettingsProcess: false, isTestHost: true))
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
