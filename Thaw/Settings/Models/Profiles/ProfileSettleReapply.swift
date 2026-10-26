//
//  ProfileSettleReapply.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// Whether the end of a settle re-applies the active profile. Re-applying the one already in place
/// would undo every drag made since.
nonisolated enum ProfileSettleReapply {
    fileprivate static let diagLog = DiagLog(category: "ProfileSettleReapply")

    static func shouldReapply(activeProfileID: UUID?, lastSettledProfileID: UUID?) -> Bool {
        guard let activeProfileID else { return false }
        return activeProfileID != lastSettledProfileID
    }

    /// What the end of a settle does with the active profile.
    enum Step: Equatable {
        /// Apply it, because the last settle left another profile in place.
        case reapply
        /// A display switch applies the profile during the settle, and applying it again would run its hooks
        /// and snapshot twice. Its layout waits for the settling task, so the settle must not wait for it.
        case leavePendingApply
        /// Leave it, so drags made since it was applied survive.
        case keep
    }

    static func step(activeProfileID: UUID?, lastSettledProfileID: UUID?, pendingApplyProfileID: UUID?) -> Step {
        guard let activeProfileID else { return .keep }
        if pendingApplyProfileID == activeProfileID {
            return .leavePendingApply
        }
        return shouldReapply(activeProfileID: activeProfileID, lastSettledProfileID: lastSettledProfileID)
            ? .reapply : .keep
    }

    /// The profile the last settle left in place, kept across launches.
    struct Record {
        static let key = Defaults.Key.lastSettledProfileID.rawValue

        private let stored: StoredProfileID

        init(defaults: UserDefaults = Defaults.store) {
            stored = StoredProfileID(key: Self.key, defaults: defaults)
        }

        var lastSettledProfileID: UUID? {
            get { stored.id }
            nonmutating set { stored.id = newValue }
        }

        /// Records the active profile and says what this settle does with it.
        func settle(activeProfileID: UUID?, pendingApplyProfileID: UUID?) -> Step {
            let last = lastSettledProfileID
            let step = ProfileSettleReapply.step(
                activeProfileID: activeProfileID,
                lastSettledProfileID: last,
                pendingApplyProfileID: pendingApplyProfileID
            )
            lastSettledProfileID = activeProfileID
            if let activeProfileID {
                let verb = switch step {
                case .reapply: "applying"
                case .leavePendingApply: "leaving the running apply of"
                case .keep: "keeping"
                }
                ProfileSettleReapply.diagLog.info(
                    "settle: \(verb) profile \(activeProfileID.uuidString) " +
                        "(last settled \(last?.uuidString ?? "none"))"
                )
            }
            return step
        }
    }
}
