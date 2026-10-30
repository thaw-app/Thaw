//
//  DisplaySpacingApplyHost.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// What a spacing apply drives outside the display settings: the spacing manager, the settling
/// period around a relaunch wave and the active profile's layout pass. Tests pass stand-ins, so
/// nothing is written to disk, no app relaunches and no alert is shown.
@MainActor
struct DisplaySpacingApplyHost {
    let spacingManager: MenuBarItemSpacingManager
    /// Writes the spacing and, when asked, relaunches the apps that read it.
    let applyOffset: @MainActor (_ forceRelaunch: Bool, _ relaunchApps: Bool) async throws -> MenuBarItemSpacingManager.ApplyOutcome
    let startSettling: @MainActor (_ reason: String, _ expectedBundleIDs: Set<String>) -> Void
    let cancelSettling: @MainActor (_ reason: String) -> Void
    let reapplyActiveProfile: @MainActor () -> Void
    /// Asks before a relaunch wave; nil shows the display settings' own alert.
    var confirmRelaunch: (@MainActor () -> Bool)?
}

extension DisplaySpacingApplyHost {
    /// The app's own subsystems. The app state is held weakly because it owns the display settings.
    init(appState: AppState) {
        let spacingManager = appState.spacingManager
        self.init(
            spacingManager: spacingManager,
            applyOffset: { try await spacingManager.applyOffset(forceRelaunch: $0, relaunchApps: $1) },
            startSettling: { [weak appState] in appState?.itemManager.startSettlingPeriod(reason: $0, expectedBundleIDs: $1) },
            cancelSettling: { [weak appState] in appState?.itemManager.cancelSettlingPeriod(reason: $0) },
            reapplyActiveProfile: { [weak appState] in appState?.profileManager.reapplyActiveProfile() }
        )
    }
}
