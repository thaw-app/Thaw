//
//  ProfileLaunchApply.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Whether a profile switch at launch applies the profile's layout.
///
/// Applying the profile already in place at launch would undo every layout
/// change made since it was saved.
nonisolated enum ProfileLaunchApply {
    /// Only the first switch of a launch, made while nothing is active yet,
    /// can find its profile already in place.
    static func applies(
        profileID: UUID,
        activeProfileID: UUID?,
        lastActiveProfileID: UUID?,
        reappliesAtLaunch: Bool
    ) -> Bool {
        guard activeProfileID == nil, profileID == lastActiveProfileID else { return true }
        return reappliesAtLaunch
    }

    /// The profile that was active last, kept across launches.
    struct Record {
        static let key = Defaults.Key.lastActiveProfileID.rawValue

        private let stored: StoredProfileID

        init(defaults: UserDefaults = Defaults.store) {
            stored = StoredProfileID(key: Self.key, defaults: defaults)
        }

        var lastActiveProfileID: UUID? {
            get { stored.id }
            nonmutating set { stored.id = newValue }
        }

        /// Marks a profile kept at launch as settled too, so the end of the
        /// startup settle doesn't apply it after all.
        func keep(_ profileID: UUID) {
            lastActiveProfileID = profileID
            ProfileSettleReapply.Record(defaults: stored.defaults).lastSettledProfileID = profileID
        }
    }
}
