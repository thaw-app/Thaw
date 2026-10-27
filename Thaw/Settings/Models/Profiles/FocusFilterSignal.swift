//
//  FocusFilterSignal.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Any process can post the Focus filter notifications, so they only wake Thaw up.
/// The system's own Focus filter state decides whether a profile applies or Focus has ended.
struct FocusFilterSignal {
    enum Action: Equatable {
        case apply(profileID: String)
        case revert
        case ignore
    }

    /// The profile ID the active Focus filter asks for, or nil when no Focus filter is active.
    let readActiveProfileID: () async -> String?

    static let system = FocusFilterSignal {
        do {
            return try await ThawFocusFilter.current.profile?.id
        } catch {
            return nil
        }
    }

    /// Applies what the system reports, and reverts only once the system reports no Focus profile.
    static nonisolated func action(systemProfileID: String?, focusFilterActive: Bool) -> Action {
        if let systemProfileID, UUID(uuidString: systemProfileID) != nil {
            return .apply(profileID: systemProfileID)
        }
        return focusFilterActive ? .revert : .ignore
    }

    func action(focusFilterActive: Bool) async -> Action {
        await Self.action(systemProfileID: readActiveProfileID(), focusFilterActive: focusFilterActive)
    }
}
