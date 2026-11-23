//
//  AppState+SettingsProcess.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

extension AppState {
    /// Shows Settings, What's New or the welcome in the settings process when the window runs there.
    /// False for other windows, and while the app's own copy is open: once Settings moves here
    /// for a page only the app shows, it stays until it closes.
    func showsInSettingsProcess(_ id: ThawWindowIdentifier, isOpenHere: Bool) -> Bool {
        guard !isOpenHere, let pane = settingsProcessPane(for: id) else { return false }
        let shown = settingsProcessHost.show(pane: pane, simpleMode: settings.general.simpleMode)
        if shown {
            // Callers make the app regular for its window first; the settings process has its own Dock icon.
            restoreAccessoryPolicyIfUnused()
        }
        if shown, id == .permissions {
            // The target tells the process to replay the welcome.
            replayRequested = false
        }
        return shown
    }

    /// Closing Settings hands focus back unless another Thaw window, such as What's New, is open or opening.
    /// Settings itself is still in openWindows when this runs.
    nonisolated static func shouldDeactivateAfterSettingsClosed(
        openWindows: Set<ThawWindowIdentifier>,
        pendingWindows: Set<ThawWindowIdentifier>
    ) -> Bool {
        openWindows.subtracting([.settings]).isEmpty && pendingWindows.isEmpty
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
