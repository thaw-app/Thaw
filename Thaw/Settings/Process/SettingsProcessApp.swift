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
    private lazy var session = SettingsProcessSession(
        navigationState: appState.navigationState,
        side: SettingsProcessSession.ProcessSide(
            reloadSettings: { [appState] in appState.settings.loadStoredValues() },
            showSettings: { [appState] in
                NSApp.activate()
                appState.openWindow(.settings)
            },
            updatesStateChanged: { [appState] canCheck, lastCheck in
                appState.updatesManager.canCheckForUpdates = canCheck
                appState.updatesManager.lastUpdateCheckDate = lastCheck
            },
            terminate: { NSApp.terminate(nil) }
        )
    )
    private let appPID = getppid()

    override init() {
        super.init()
        appState.settings.loadStoredValues()
        session.selectLaunchPane(in: ProcessInfo.processInfo.arguments)
        appState.updatesManager.forwardCheck = { [weak self] in
            // The updater's windows belong to the app, which may only come forward if this process lets it.
            if let app = self.flatMap({ NSRunningApplication(processIdentifier: $0.appPID) }) {
                NSApp.yieldActivation(to: app)
            }
            self?.session.send(.checkForUpdates)
        }
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
        ProcessDisplayName.set(String(localized: "\(Constants.displayName) Settings"))
        NSApp.activate()
        // The app writes to standard input. When it closes, the app has gone, and so does this process.
        session.start(input: .standardInput, output: .standardOutput, onClose: { exit(0) })
        appState.openWindow(.settings)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        session.willTerminate(hasOpenWindow: NSApp.windows.contains { $0.isVisible && $0.canBecomeMain })
        return .terminateNow
    }
}
