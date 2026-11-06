//
//  GroupMoveRefusal.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// Why a whole-group section move was refused.
///
/// A group is indivisible, so a move that cannot apply to every member must not
/// apply to any of them. Carrying the offending item, rather than a bare bool,
/// is what lets the UI name the app that blocked the move; a raw identifier like
/// com.bjango.istatmenus.status:Battery is not a user-facing string.
typealias GroupMoveRefusal = MenuBarGroupMoveRefusal

extension MenuBarGroupMoveRefusal {
    /// A short, user-facing explanation naming the app rather than an identifier.
    nonisolated var localizedReason: String {
        switch self {
        case let .protectedMember(item):
            String(
                localized: "“\(item.displayName)” can’t be moved out of the menu bar.",
                comment: "Reason a group move was refused: a protected item"
            )
        case let .hidingUnsupported(item):
            String(
                localized: "macOS doesn’t let \(Constants.displayName) hide “\(item.displayName)”.",
                comment: "Reason a group move was refused: hiding unsupported for this app"
            )
        case let .notHideable(item):
            String(
                localized: "“\(item.displayName)” can’t be hidden.",
                comment: "Reason a group move was refused: item not hideable"
            )
        case .hidingUnavailable:
            String(
                localized: "Hiding isn’t available on this version of macOS.",
                comment: "Reason a group move was refused: hiding unavailable"
            )
        // Two strings rather than an inflected one: automatic grammar agreement
        // only runs on AttributedString, and the verb has to agree as well.
        case .unresolvedMembers(1):
            String(
                localized: "1 item in this group isn’t in the menu bar right now. Open the missing app, then try again.",
                comment: "Reason a group move was refused: one member missing"
            )
        case let .unresolvedMembers(missingCount):
            String(
                localized: "\(missingCount) items in this group aren’t in the menu bar right now. Open the missing apps, then try again.",
                comment: "Reason a group move was refused: several members missing"
            )
        }
    }
}
