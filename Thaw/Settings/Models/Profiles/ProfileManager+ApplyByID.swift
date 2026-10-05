//
//  ProfileManager+ApplyByID.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

extension ProfileManager {
    /// Applies the profile and waits for its layout task, for the Shortcuts intent and thaw://apply-profile.
    /// Read layoutDidNotRun afterwards to learn whether the layout half ran.
    @discardableResult
    func applyProfileAwaitingLayout(id: UUID, to appState: AppState) async throws -> Profile {
        let loaded = try loadProfile(id: id)

        // Capture the outgoing ID before assignment so hooks receive the correct THAW_PREVIOUS_PROFILE_ID.
        let previousID = activeProfileID
        activeProfileID = id
        applyProfile(loaded, to: appState, previousProfileID: previousID)
        await layoutTask?.value
        return loaded
    }
}
