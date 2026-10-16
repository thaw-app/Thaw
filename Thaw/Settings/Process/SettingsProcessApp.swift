//
//  SettingsProcessApp.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// `Thaw --settings <pane>`: Settings in a process the app started, with AppState built but never
/// launched. It ends when its last window closes, What's New and Acknowledgements included.
struct SettingsProcessApp: App {
    @NSApplicationDelegateAdaptor private var delegate: SettingsProcessDelegate

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(SettingsProcessRoute.launchArgument)
    }

    var body: some Scene {
        WindowActionBridge(registerWindowActions: delegate.appState.registerWindowActions)
        SettingsWindow(appState: delegate.appState)
        WhatsNewWindow(appState: delegate.appState)
        AcknowledgementsWindow(appState: delegate.appState)
    }
}

@MainActor
private final class SettingsProcessDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var link: SettingsLinkEndpoint?
    private var paneWatch: Task<Void, Never>?
    /// Set when this process closes itself, so its own exit isn't taken for the user's Quit.
    private var isClosingItself = false
    private let appPID = getppid()

    override init() {
        super.init()
        appState.settings.loadStoredValues()
        let pane = SettingsProcessRoute.launchPane(in: ProcessInfo.processInfo.arguments)
        if let pane, let identifier = SettingsNavigationIdentifier(rawValue: pane) {
            appState.navigationState.settingsNavigationIdentifier = identifier
        }
        appState.updatesManager.forwardCheck = { [weak self] in
            // The updater's windows belong to the app, which may only come forward if this process lets it.
            if let app = self.flatMap({ NSRunningApplication(processIdentifier: $0.appPID) }) {
                NSApp.yieldActivation(to: app)
            }
            self?.link?.send(.checkForUpdates)
        }
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
        ProcessDisplayName.set(String(localized: "\(Constants.displayName) Settings"))
        NSApp.activate()
        // The app writes to standard input. When it closes, the app has gone, and so does this process.
        link = SettingsLinkEndpoint(
            input: .standardInput,
            output: .standardOutput,
            onMessage: { [weak self] message in self?.receive(message) },
            onClose: { exit(0) }
        )
        watchPane()
        appState.openWindow(.settings)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    /// Quit with a window still open is the user's Quit, which quits the app as it did
    /// when Settings was one of its windows.
    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        if !isClosingItself, NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            link?.send(.quit)
        }
        return .terminateNow
    }

    private func receive(_ message: SettingsLinkMessage) {
        switch message {
        case let .show(pane):
            if let pane, let identifier = SettingsNavigationIdentifier(rawValue: pane) {
                appState.navigationState.settingsNavigationIdentifier = identifier
            }
            NSApp.activate()
            appState.openWindow(.settings)
        case .settingsChanged:
            link?.reloading(appState.settings.loadStoredValues)
        case let .updatesState(canCheck, lastCheck):
            appState.updatesManager.canCheckForUpdates = canCheck
            appState.updatesManager.lastUpdateCheckDate = lastCheck
        case .openInApp, .pageChanged, .checkForUpdates, .quit:
            break
        }
    }

    /// Tells the app each pane shown here, and hands it the panes that need the running app.
    private func watchPane() {
        let navigationState = appState.navigationState
        paneWatch = Task { @MainActor [weak self] in
            for await identifier in Observations({ navigationState.settingsNavigationIdentifier }) {
                guard let self else { return }
                guard SettingsProcessRoute.ownProcessPanes.contains(identifier.rawValue) else {
                    link?.send(.openInApp(pane: identifier.rawValue))
                    isClosingItself = true
                    NSApp.terminate(nil)
                    return
                }
                link?.send(.pageChanged(pane: identifier.rawValue))
            }
        }
    }
}
