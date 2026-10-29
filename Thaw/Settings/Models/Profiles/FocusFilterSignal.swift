//
//  FocusFilterSignal.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppIntents
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
    /// Throws when the system could not be read, which is not the same as no Focus filter.
    let readActiveProfileID: () async throws -> String?

    static let system = FocusFilterSignal {
        try await profileID { try await ThawFocusFilter.current.profile?.id }
    }

    /// The system reports no active Focus filter as notFound; any other error is a failed read.
    static func profileID(reading read: () async throws -> String?) async throws -> String? {
        do {
            return try await read()
        } catch SetFocusFilterIntentError.notFound {
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

    /// A failed read changes nothing, so a transient error can't end the Focus profile.
    func action(focusFilterActive: Bool) async -> Action {
        let systemProfileID: String?
        do {
            systemProfileID = try await readActiveProfileID()
        } catch {
            return .ignore
        }
        return Self.action(systemProfileID: systemProfileID, focusFilterActive: focusFilterActive)
    }
}
