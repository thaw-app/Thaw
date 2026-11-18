//
//  AppState+SettingsProcess.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

extension AppState {
    /// Shows Settings or What's New in its own process when that is on and, for Settings, the pane runs there.
    /// False for every other window, and while the app's own copy of the window is open.
    func showsInSettingsProcess(_ id: ThawWindowIdentifier, isOpenHere: Bool) -> Bool {
        if id == .settings {
            watchSettingsHandBack()
        }
        guard !isOpenHere, let pane = settingsProcessPane(for: id) else { return false }
        let shown = settingsProcessHost.show(pane: pane, simpleMode: settings.general.simpleMode)
        if shown, id == .permissions {
            // The process replays the welcome itself, as told by the target.
            replayRequested = false
        }
        return shown
    }

    /// In the settings process, opens a window the app sent: one of SettingsProcessRoute.windowTargets.
    func openSettingsProcessWindow(_ target: String) {
        switch target {
        case SettingsProcessRoute.whatsNew:
            openWindow(.whatsNew)
        case SettingsProcessRoute.welcomeAgain:
            replayRequested = true
            openWindow(.permissions)
        default:
            openWindow(.permissions)
        }
    }

    /// What the settings process opens for a window, or nil for one only the app has.
    private func settingsProcessPane(for id: ThawWindowIdentifier) -> String? {
        switch id {
        case .settings: navigationState.settingsNavigationIdentifier.rawValue
        case .whatsNew: SettingsProcessRoute.whatsNew
        case .permissions: replayRequested ? SettingsProcessRoute.welcomeAgain : SettingsProcessRoute.permissions
        default: nil
        }
    }

    /// While the app's own Settings window is up, a move to a page the settings process shows hands the
    /// window to it. The app's window closes once the process says it shows the page, so Settings stays up.
    func watchSettingsHandBack() {
        guard !SettingsProcessApp.isRequested, settingsProcessHost.handBack.watch == nil else { return }
        let navigationState = navigationState
        settingsProcessHost.handBack.watch = Task { @MainActor [weak self] in
            for await pane in Observations({ navigationState.settingsNavigationIdentifier }) {
                guard let self else { return }
                guard navigationState.isSettingsPresented, !settingsProcessHost.handBack.isPending,
                      settingsProcessHost.show(pane: pane.rawValue, simpleMode: settings.general.simpleMode)
                else { continue }
                settingsProcessHost.handBack.isPending = true
            }
        }
    }

    /// Closes the app's Settings window once the settings process shows the page it was handed.
    private func finishSettingsHandBack() {
        guard settingsProcessHost.handBack.isPending else { return }
        settingsProcessHost.handBack.isPending = false
        dismissWindow(.settings)
    }

    /// What the app does when the settings process asks.
    func settingsProcessAppSide() -> SettingsProcessHost.AppSide {
        SettingsProcessHost.AppSide(
            reloadSettings: { [weak self] in
                self?.settings.loadStoredValues()
                self?.updatesManager.storedPreferencesChanged()
            },
            openInApp: { [weak self] pane in self?.openSettingsInApp(pane: pane) },
            pageChanged: { [weak self] pane in
                if let identifier = SettingsNavigationIdentifier(storedValue: pane) {
                    self?.navigationState.settingsNavigationIdentifier = identifier
                }
                self?.finishSettingsHandBack()
            },
            checkForUpdates: { [weak self] in self?.updatesManager.checkForUpdates() },
            quit: { ApplicationTermination.request() },
            updatesState: { [weak self] in
                .updatesState(
                    canCheck: self?.updatesManager.canCheckForUpdates ?? false,
                    lastCheck: self?.updatesManager.lastUpdateCheckDate
                )
            },
            features: SettingsLinkFeatures.app(self)
        )
    }

    /// A pane the settings process handed back because it needs the running app.
    private func openSettingsInApp(pane: String) {
        if let identifier = SettingsNavigationIdentifier(storedValue: pane) {
            navigationState.settingsNavigationIdentifier = identifier
        }
        openWindow(.settings, allowSettingsProcess: false)
    }
}

/// The app's side of handing its Settings window back to the settings process.
@MainActor
final class SettingsHandBack {
    var watch: Task<Void, Never>?
    /// The process was asked for a page, and the app's window stays up until it shows it.
    var isPending = false
}
