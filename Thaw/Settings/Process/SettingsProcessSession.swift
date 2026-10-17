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
    private var link: SettingsLinkEndpoint?
    private var paneWatch: Task<Void, Never>?
    /// Set when this process closes itself, so its own exit isn't taken for the user's Quit.
    private(set) var isClosingItself = false

    init(navigationState: AppNavigationState, side: ProcessSide) {
        self.navigationState = navigationState
        self.side = side
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
            link?.send(.openInApp(pane: identifier.rawValue))
            isClosingItself = true
            side.terminate()
            return false
        }
        link?.send(.pageChanged(pane: identifier.rawValue))
        return true
    }
}
