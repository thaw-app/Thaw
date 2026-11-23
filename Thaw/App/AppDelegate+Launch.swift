//
//  AppDelegate+Launch.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

extension AppDelegate {
    /// Starts the app against the live system. Returns false, doing nothing, when the app is only hosting tests.
    func launchAppState() -> Bool {
        guard !TestHosting.isActiveInProcess else { return false }

        ConflictingAppDetector.showWarningIfNeeded()

        switch appState.permissions.permissionsState {
        case .hasAll:
            appState.permissions.diagLog.debug("Passed all permissions checks")
            appState.launch(withPermissions: true)
        case .hasRequired:
            appState.permissions.diagLog.debug("Passed required permissions checks")
            appState.launch(withPermissions: true)
        case .missing:
            appState.permissions.diagLog.debug("Failed required permissions checks")
            appState.launch(withPermissions: false)
        }
        return true
    }
}
