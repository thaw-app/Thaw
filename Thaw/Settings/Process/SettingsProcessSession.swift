//
//  SettingsProcessSession.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The settings process's end of the link: what it does when the app asks, and the panes it tells the app about.
@MainActor
final class SettingsProcessSession {
    /// What the settings process does for the app.
    struct ProcessSide {
        var reloadSettings: () -> Void
        var showSettings: () -> Void
        var updatesStateChanged: (_ canCheck: Bool, _ lastCheck: Date?) -> Void
        var terminate: () -> Void
    }

    private let navigationState: AppNavigationState
    private let side: ProcessSide
    /// How long the window stays up after a hand-over when the app never says its window is up.
    private let handOverTimeout: Duration
    private var link: SettingsLinkEndpoint?
    private var paneWatch: Task<Void, Never>?
    private var handOver: Task<Void, Never>?
    /// Set when this process closes itself, so its own exit isn't taken for the user's Quit.
    private(set) var isClosingItself = false

    init(navigationState: AppNavigationState, side: ProcessSide, handOverTimeout: Duration = .seconds(3)) {
        self.navigationState = navigationState
        self.side = side
        self.handOverTimeout = handOverTimeout
    }

    /// Opens on the pane named in the launch arguments, when it names one.
    func selectLaunchPane(in arguments: [String]) {
        select(SettingsProcessRoute.launchPane(in: arguments))
    }

    /// Reads the app's messages from input and writes to output, then tells the app each pane shown.
    func start(input: FileHandle, output: FileHandle, onClose: @escaping @MainActor () -> Void) {
        link = SettingsLinkEndpoint(
            input: input,
            output: output,
            onMessage: { [weak self] message in self?.receive(message) },
            onClose: onClose
        )
        watchPane()
    }

    func send(_ message: SettingsLinkMessage) {
        link?.send(message)
    }

    /// Quit with a window still open is the user's Quit, which quits the app as it did
    /// when Settings was one of its windows.
    func willTerminate(hasOpenWindow: Bool) {
        if !isClosingItself, hasOpenWindow {
            link?.send(.quit)
        }
    }

    private func select(_ pane: String?) {
        if let pane, let identifier = SettingsNavigationIdentifier(rawValue: pane) {
            navigationState.settingsNavigationIdentifier = identifier
        }
    }

    private func receive(_ message: SettingsLinkMessage) {
        switch message {
        case let .show(pane):
            select(pane)
            side.showSettings()
        case .settingsChanged:
            link?.reloading(side.reloadSettings)
        case let .updatesState(canCheck, lastCheck):
            side.updatesStateChanged(canCheck, lastCheck)
        case .shownInApp:
            closeAfterHandOver()
        case .openInApp, .pageChanged, .checkForUpdates, .quit:
            break
        }
    }

    /// Tells the app each pane shown here, and hands it the panes that need the running app.
    private func watchPane() {
        let navigationState = navigationState
        paneWatch = Task { @MainActor [weak self] in
            for await identifier in Observations({ navigationState.settingsNavigationIdentifier }) {
                guard let self, paneShown(identifier) else { return }
            }
        }
    }

    /// False once the pane has gone to the app and this process is closing.
    private func paneShown(_ identifier: SettingsNavigationIdentifier) -> Bool {
        guard SettingsProcessRoute.ownProcessPanes.contains(identifier.rawValue) else {
            handOverToApp(identifier.rawValue)
            return false
        }
        link?.send(.pageChanged(pane: identifier.rawValue))
        return true
    }

    /// Sends the pane to the app and keeps this window up until the app's is, so Settings
    /// doesn't disappear for the moment the app takes to open its window.
    private func handOverToApp(_ pane: String) {
        link?.send(.openInApp(pane: pane))
        isClosingItself = true
        handOver = Task { @MainActor [weak self, handOverTimeout] in
            guard (try? await Task.sleep(for: handOverTimeout)) != nil else { return }
            self?.closeAfterHandOver()
        }
    }

    /// Does nothing unless a hand-over is waiting, and closes this process once.
    private func closeAfterHandOver() {
        guard let handOver else { return }
        handOver.cancel()
        self.handOver = nil
        side.terminate()
    }
}
