//
//  ProfileManager+LayoutBehavior.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

extension ProfileManager {
    /// Makes the profile active without applying it when Thaw starts with the
    /// profile that was active when it quit. See ProfileLaunchApply.
    func keepsLiveLayoutAtLaunch(_ meta: ProfileMetadata) -> Bool {
        guard !ProfileLaunchApply.applies(
            profileID: meta.id,
            activeProfileID: activeProfileID,
            lastActiveProfileID: launchRecord?.lastActiveProfileID,
            reappliesAtLaunch: meta.reappliesAtLaunch
        ) else { return false }
        diagLog.info("Keeping the live layout: \(meta.name) was active when Thaw quit")
        activeProfileID = meta.id
        launchRecord?.keep(meta.id)
        return true
    }
}
