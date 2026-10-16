//
//  AppState+SettingsProcess.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

extension AppState {
    /// Shows Settings in its own process when that is on and the pane runs there.
    /// False for every other window, and while the app's own Settings window is open.
    func showsInSettingsProcess(_ id: ThawWindowIdentifier, isOpenHere: Bool) -> Bool {
        guard id == .settings, !isOpenHere else { return false }
        return settingsProcessHost.show(
            pane: navigationState.settingsNavigationIdentifier.rawValue,
            simpleMode: settings.general.simpleMode
        )
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
                if let identifier = SettingsNavigationIdentifier(rawValue: pane) {
                    self?.navigationState.settingsNavigationIdentifier = identifier
                }
            },
            checkForUpdates: { [weak self] in self?.updatesManager.checkForUpdates() },
            quit: { ApplicationTermination.request() },
            updatesState: { [weak self] in
                .updatesState(
                    canCheck: self?.updatesManager.canCheckForUpdates ?? false,
                    lastCheck: self?.updatesManager.lastUpdateCheckDate
                )
            }
        )
    }

    /// A pane the settings process handed back because it needs the running app.
    private func openSettingsInApp(pane: String) {
        if let identifier = SettingsNavigationIdentifier(rawValue: pane) {
            navigationState.settingsNavigationIdentifier = identifier
        }
        openWindow(.settings, allowSettingsProcess: false)
    }
}
