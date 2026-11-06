//
//  ProfileLaunchGate.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// ProfileLaunchApply for one launch: the profile active at quit is read
/// once, and only the startup switch can find it still in place.
@MainActor
final class ProfileLaunchGate {
    /// Nil for managers pointed at a test directory, which must not write the user's defaults.
    let record: ProfileLaunchApply.Record?
    private var activeAtQuit: UUID?

    init(record: ProfileLaunchApply.Record?) {
        self.record = record
        activeAtQuit = record?.lastActiveProfileID
    }

    /// Whether the profile becomes active without its layout being applied.
    /// A kept profile is marked settled too.
    func keepsLiveLayout(_ meta: ProfileMetadata, activeProfileID: UUID?) -> Bool {
        defer { activeAtQuit = nil }
        let keeps = !ProfileLaunchApply.applies(
            profileID: meta.id,
            activeProfileID: activeProfileID,
            lastActiveProfileID: activeAtQuit,
            reappliesAtLaunch: meta.reappliesAtLaunch
        )
        if keeps {
            record?.keep(meta.id)
        }
        return keeps
    }

    /// Ends the launch, so every later switch applies its profile.
    func close() {
        activeAtQuit = nil
    }
}
