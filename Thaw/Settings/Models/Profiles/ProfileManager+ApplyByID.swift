//
//  ProfileManager+ApplyByID.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

extension ProfileManager {
    /// Applies the profile and waits for its layout task, for the Shortcuts intent, thaw://apply-profile and the Profiles page.
    /// Read layoutDidNotRun afterwards to learn whether the layout half ran.
    /// Pass spacingRelaunchApproved only after the user agreed to restart apps for this apply.
    @discardableResult
    func applyProfileAwaitingLayout(id: UUID, to appState: AppState, spacingRelaunchApproved: Bool = false) async throws -> Profile {
        let loaded = try switchToProfile(id: id, on: appState, spacingRelaunchApproved: spacingRelaunchApproved)
        await layoutTask?.value
        return loaded
    }

    /// Loads the profile, makes it active and starts applying it. Nothing changes when the load fails.
    @discardableResult
    func switchToProfile(id: UUID, on appState: AppState, relaunchesApps: Bool = true, spacingRelaunchApproved: Bool = false) throws -> Profile {
        let loaded = try loadProfile(id: id)

        // Capture the outgoing ID before assignment so hooks receive the correct THAW_PREVIOUS_PROFILE_ID.
        let previousID = activeProfileID
        activeProfileID = id
        applyProfile(loaded, to: appState, previousProfileID: previousID, relaunchesApps: relaunchesApps, spacingRelaunchApproved: spacingRelaunchApproved)
        return loaded
    }
}
