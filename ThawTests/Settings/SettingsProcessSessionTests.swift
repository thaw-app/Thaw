//
//  SettingsProcessSessionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// The settings process's end of the link, with the app's end played by pipes in this process
/// and the pane saved to a throwaway defaults suite.
@Suite("Settings process session", .serialized)
@MainActor
final class SettingsProcessSessionTests {
    private final class Calls {
        var reloads = 0
        var shows = 0
        var updates = [(canCheck: Bool, lastCheck: Date?)]()
        var terminations = 0
        var closes = 0
    }

    private let suites = ScratchSuites(prefix: "SettingsProcessSessionTests")
    private let previousStore = Defaults.store
    private let calls = Calls()
    private let toProcess = Pipe()
    private let fromProcess = Pipe()
    private var appReceived = [SettingsLinkMessage]()
    private var appEnd: SettingsLinkEndpoint?

    init() throws {
        Defaults.store = try #require(suites.make())
    }

    isolated deinit {
        appEnd?.close()
        Defaults.store = previousStore
    }

    /// What reached the app, leaving out the notices any defaults write in the test process sends.
    private var appMessages: [SettingsLinkMessage] {
        appReceived.filter { $0 != .settingsChanged }
    }

    private func makeSession(_ navigation: AppNavigationState, handOverTimeout: Duration = .seconds(30)) -> SettingsProcessSession {
        let calls = calls
        return SettingsProcessSession(
            navigationState: navigation,
            side: SettingsProcessSession.ProcessSide(
                reloadSettings: { calls.reloads += 1 },
                showSettings: { calls.shows += 1 },
                updatesStateChanged: { calls.updates.append(($0, $1)) },
                terminate: { calls.terminations += 1 }
            ),
            handOverTimeout: handOverTimeout
        )
    }

    private func start(_ session: SettingsProcessSession) {
        let calls = calls
        session.start(
            input: toProcess.fileHandleForReading,
            output: fromProcess.fileHandleForWriting,
            onClose: { calls.closes += 1 }
        )
        appEnd = SettingsLinkEndpoint(
            input: fromProcess.fileHandleForReading,
            output: toProcess.fileHandleForWriting,
            onMessage: { [weak self] in self?.appReceived.append($0) }
        )
    }

    @Test("The launch argument picks the pane, and a name that isn't a pane is ignored")
    func launchPane() {
        let navigation = AppNavigationState()
        let session = makeSession(navigation)
        session.selectLaunchPane(in: ["Thaw", "--settings", "Privacy"])
        #expect(navigation.settingsNavigationIdentifier == .privacy)
        session.selectLaunchPane(in: ["Thaw", "--settings", "Nowhere"])
        session.selectLaunchPane(in: ["Thaw"])
        #expect(navigation.settingsNavigationIdentifier == .privacy)
    }

    @Test("Each pane shown here is reported to the app")
    func panesAreReported() async {
        let navigation = AppNavigationState()
        navigation.settingsNavigationIdentifier = .general
        let session = makeSession(navigation)
        start(session)
        #expect(await settingsLinkWait { appMessages.contains(.pageChanged(pane: "General")) })
        navigation.settingsNavigationIdentifier = .about
        #expect(await settingsLinkWait { appMessages.contains(.pageChanged(pane: "About")) })
        #expect(calls.terminations == 0)
    }

    @Test("A pane that needs the app goes to the app, and this process closes once the app's window is up")
    func appPaneHandsOver() async {
        let navigation = AppNavigationState()
        navigation.settingsNavigationIdentifier = .general
        let session = makeSession(navigation)
        start(session)
        navigation.settingsNavigationIdentifier = .menuBarLayout
        #expect(await settingsLinkWait { appMessages.contains(.openInApp(pane: "Menu Bar Layout")) })
        #expect(session.isClosingItself)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(calls.terminations == 0, "The window stays up until the app's is")
        appEnd?.send(.shownInApp)
        appEnd?.send(.shownInApp)
        #expect(await settingsLinkWait { calls.terminations == 1 })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(calls.terminations == 1, "It closes once")
        session.willTerminate(hasOpenWindow: true)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!appMessages.contains(.quit), "Closing itself is not the user's Quit")
    }

    @Test("The app's messages show the window, reload settings and carry the updater state")
    func appMessagesAreHandled() async {
        let navigation = AppNavigationState()
        navigation.settingsNavigationIdentifier = .general
        let session = makeSession(navigation)
        start(session)
        let checked = Date(timeIntervalSince1970: 1_800_000_000)
        for message: SettingsLinkMessage in [
            .show(pane: "About"), .show(pane: nil), .settingsChanged,
            .updatesState(canCheck: true, lastCheck: checked),
            .openInApp(pane: "General"), .pageChanged(pane: "General"), .checkForUpdates, .quit, .shownInApp,
        ] {
            appEnd?.send(message)
        }
        #expect(await settingsLinkWait { calls.shows == 2 && calls.reloads > 0 && !calls.updates.isEmpty })
        #expect(navigation.settingsNavigationIdentifier == .about)
        #expect(calls.updates.first?.canCheck == true)
        #expect(calls.updates.first?.lastCheck == checked)
        #expect(calls.terminations == 0)
    }

    @Test("A hand-over the app never confirms still closes this process after the timeout")
    func unconfirmedHandOverTimesOut() async {
        let navigation = AppNavigationState()
        navigation.settingsNavigationIdentifier = .general
        let session = makeSession(navigation, handOverTimeout: .milliseconds(50))
        start(session)
        navigation.settingsNavigationIdentifier = .menuBarLayout
        #expect(await settingsLinkWait { calls.terminations == 1 })
        appEnd?.send(.shownInApp)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(calls.terminations == 1)
    }

    @Test("Quit with a window open quits the app too; without one it doesn't")
    func quitFollowsOpenWindows() async {
        let navigation = AppNavigationState()
        let session = makeSession(navigation)
        start(session)
        session.willTerminate(hasOpenWindow: false)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!appMessages.contains(.quit))
        session.willTerminate(hasOpenWindow: true)
        #expect(await settingsLinkWait { appMessages.contains(.quit) })
    }

    @Test("A check for updates is sent to the app")
    func sendReachesTheApp() async {
        let session = makeSession(AppNavigationState())
        start(session)
        session.send(.checkForUpdates)
        #expect(await settingsLinkWait { appMessages.contains(.checkForUpdates) })
    }

    @Test("The app closing its end ends the session")
    func appCloseEndsSession() async throws {
        let session = makeSession(AppNavigationState())
        start(session)
        appEnd?.close()
        try toProcess.fileHandleForWriting.close()
        #expect(await settingsLinkWait { calls.closes == 1 })
        _ = session
    }
}
