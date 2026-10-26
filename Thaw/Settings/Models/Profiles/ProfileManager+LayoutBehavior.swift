//
//  ProfileManager+LayoutBehavior.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

extension ProfileManager {
    /// Makes the profile active without applying it when Thaw starts with the
    /// profile that was active when it quit. See ProfileLaunchGate.
    func keepsLiveLayoutAtLaunch(_ meta: ProfileMetadata) -> Bool {
        guard launchGate.keepsLiveLayout(meta, activeProfileID: activeProfileID) else { return false }
        diagLog.info("Keeping the live layout: \(meta.name) was active when Thaw quit")
        activeProfileID = meta.id
        return true
    }

    /// keepsLiveLayoutAtLaunch(_:) for the profile with this ID, false when there is none.
    func keepsLiveLayoutAtLaunch(profileID: UUID) -> Bool {
        guard let meta = profiles.first(where: { $0.id == profileID }) else { return false }
        return keepsLiveLayoutAtLaunch(meta)
    }
}
