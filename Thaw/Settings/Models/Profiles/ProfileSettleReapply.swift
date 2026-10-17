//
//  ProfileSettleReapply.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Whether the end of a settle re-applies the active profile. Re-applying the one already in place
/// would undo every drag made since.
nonisolated enum ProfileSettleReapply {
    static func shouldReapply(activeProfileID: UUID?, lastSettledProfileID: UUID?) -> Bool {
        guard let activeProfileID else { return false }
        return activeProfileID != lastSettledProfileID
    }

    /// The profile the last settle left in place, kept across launches.
    struct Record {
        static let key = "ProfileSettleReapply.lastSettledProfileID"

        private let defaults: UserDefaults

        init(defaults: UserDefaults = .standard) {
            self.defaults = defaults
        }

        var lastSettledProfileID: UUID? {
            get { defaults.string(forKey: Self.key).flatMap(UUID.init(uuidString:)) }
            nonmutating set {
                if let newValue {
                    defaults.set(newValue.uuidString, forKey: Self.key)
                } else {
                    defaults.removeObject(forKey: Self.key)
                }
            }
        }

        /// Records the active profile and says whether this settle should apply it.
        func settle(activeProfileID: UUID?) -> Bool {
            let reapply = ProfileSettleReapply.shouldReapply(
                activeProfileID: activeProfileID,
                lastSettledProfileID: lastSettledProfileID
            )
            lastSettledProfileID = activeProfileID
            return reapply
        }
    }
}
