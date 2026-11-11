//
//  DisplaySpacingApplyHost.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// What a spacing apply drives outside the display settings: the spacing manager, the settling
/// period around a relaunch wave and the active profile's layout pass. Tests pass stand-ins.
@MainActor
struct DisplaySpacingApplyHost {
    let spacingManager: MenuBarItemSpacingManager
    /// Writes the spacing and, when asked, relaunches the apps that read it.
    let applyOffset: @MainActor (_ forceRelaunch: Bool, _ relaunchApps: Bool) async throws -> MenuBarItemSpacingManager.ApplyOutcome
    /// Reports the wave to the bar's settle, which holds restores off until relaunched apps reattach.
    let noteSettling: @MainActor (BarSettling.Disturbance) -> Void
    let reapplyActiveProfile: @MainActor () -> Void
    /// Asks before a relaunch wave; nil shows the display settings' own alert.
    var confirmRelaunch: (@MainActor () -> Bool)?
    /// Saves a spacing change to the active profile, or to every profile, so the next
    /// profile apply keeps it. Does nothing while no profile is active.
    var saveSpacingToProfiles: @MainActor (_ displayUUID: String, _ offset: Double, _ scope: SpacingProfileSaveScope) throws -> Void = { _, _, _ in
        // Stand-ins in tests save nothing.
    }
}

extension DisplaySpacingApplyHost {
    /// The app's own subsystems. The app state is held weakly because it owns the display settings.
    init(appState: AppState) {
        let spacingManager = appState.spacingManager
        self.init(
            spacingManager: spacingManager,
            applyOffset: { try await spacingManager.applyOffset(forceRelaunch: $0, relaunchApps: $1) },
            noteSettling: { [weak appState] in appState?.itemManager.barSettling.note($0) },
            reapplyActiveProfile: { [weak appState] in appState?.profileManager.reapplyActiveProfile() },
            saveSpacingToProfiles: { [weak appState] displayUUID, offset, scope in
                guard let appState, let id = appState.profileManager.activeProfileID else { return }
                switch scope {
                case .activeProfile:
                    try appState.profileManager.updateProfile(id: id, scope: .configurationOnly, appState: appState)
                case .allProfiles:
                    try appState.profileManager.updateAllProfilesItemSpacingOffset(displayUUID: displayUUID, offset: offset)
                }
            }
        )
    }
}
