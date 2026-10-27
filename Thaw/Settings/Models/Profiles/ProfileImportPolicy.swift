//
//  ProfileImportPolicy.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// What an imported profile may bring with it. A file can come from anyone, so it can't switch on
/// anything that runs code or restarts apps unasked, and it can't be big enough to stall Thaw.
enum ProfileImportPolicy {
    /// The most profiles one file may hold.
    static nonisolated let maxEntries = 100

    /// The most item identifiers kept for one section of a saved order.
    static nonisolated let maxIdentifiersPerSection = 1000

    nonisolated enum ImportError: LocalizedError, Equatable {
        case tooManyProfiles(Int)

        var errorDescription: String? {
            switch self {
            case let .tooManyProfiles(count):
                String(localized: "The file holds \(count) profiles; at most \(ProfileImportPolicy.maxEntries) can be imported at once.")
            }
        }
    }

    /// Refuses a file before any of it is written.
    static func validate(_ bundle: ProfileExportBundle) throws {
        guard bundle.entries.count <= maxEntries else {
            throw ImportError.tooManyProfiles(bundle.entries.count)
        }
    }

    /// The content with its hooks off, relaunch confirmation on, and its saved orders cut to a sane length.
    static func sanitized(_ content: ProfileContent) -> ProfileContent {
        var content = content
        content.automation = content.automation?.disabledUntilApproved
        content.confirmSpacingRelaunch = true
        content.menuBarLayout.savedSectionOrder = capped(content.menuBarLayout.savedSectionOrder)
        content.menuBarLayout.itemOrder = content.menuBarLayout.itemOrder.map(capped)
        return content
    }

    private static func capped(_ order: [String: [String]]) -> [String: [String]] {
        order.mapValues { identifiers in
            identifiers.count > maxIdentifiersPerSection
                ? Array(identifiers.prefix(maxIdentifiersPerSection))
                : identifiers
        }
    }
}
