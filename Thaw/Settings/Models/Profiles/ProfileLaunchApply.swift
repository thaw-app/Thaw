//
//  ProfileLaunchApply.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Whether a profile switch at launch applies the profile's layout.
///
/// A display, Space or Focus switches to its profile as Thaw starts. When that
/// profile was already active when Thaw quit, applying it put back the layout
/// it was saved with and undid every change made since (2026-10-22 report: an
/// item dragged into Always Hidden went back to Hidden after each logout).
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

        private let defaults: UserDefaults

        init(defaults: UserDefaults = Defaults.store) {
            self.defaults = defaults
        }

        var lastActiveProfileID: UUID? {
            get { defaults.string(forKey: Self.key).flatMap(UUID.init(uuidString:)) }
            nonmutating set {
                if let newValue {
                    defaults.set(newValue.uuidString, forKey: Self.key)
                } else {
                    defaults.removeObject(forKey: Self.key)
                }
            }
        }

        /// Marks a profile kept at launch as settled too, so the end of the
        /// startup settle doesn't apply it after all.
        func keep(_ profileID: UUID) {
            lastActiveProfileID = profileID
            ProfileSettleReapply.Record(defaults: defaults).lastSettledProfileID = profileID
        }
    }
}
