//
//  GroupMoveFeasibility.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

// MARK: - GroupMoveRefusal

/// Why a whole-group section move was refused.
///
/// A group is indivisible, so a move that cannot apply to every member must not
/// apply to any of them. Carrying the offending item — rather than a bare bool —
/// is what lets the UI name the app that blocked the move; a raw identifier like
/// `com.bjango.istatmenus.status:Battery` is not a user-facing string.
nonisolated enum GroupMoveRefusal: Equatable {
    /// A control item, one of Thaw's own items, or a fixed layout anchor.
    case protectedMember(item: MenuBarItem)
    /// An app on the hiding-unsupported denylist.
    case hidingUnsupported(item: MenuBarItem)
    /// The item reports that it cannot be hidden on this backend.
    case notHideable(item: MenuBarItem)
    /// Hiding is unavailable entirely (Assessment Mode not usable on this build).
    case hidingUnavailable
    /// Fewer live members resolved than the group has. Refusing is the only safe
    /// answer: moving the members we found would split the group.
    case unresolvedMembers(missingCount: Int)

    /// The item that blocked the move, when there is one.
    var blockingItem: MenuBarItem? {
        switch self {
        case let .protectedMember(item), let .hidingUnsupported(item), let .notHideable(item):
            item
        case .hidingUnavailable, .unresolvedMembers:
            nil
        }
    }

    /// A short, user-facing explanation naming the app rather than an identifier.
    var localizedReason: String {
        switch self {
        case let .protectedMember(item):
            String(
                localized: "“\(item.displayName)” can’t be moved out of the menu bar.",
                comment: "Reason a group move was refused: a protected item"
            )
        case let .hidingUnsupported(item):
            String(
                localized: "“\(item.displayName)” can’t be hidden by macOS.",
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
        case let .unresolvedMembers(missingCount):
            String(
                localized: "\(missingCount) item(s) in this group aren’t currently in the menu bar.",
                comment: "Reason a group move was refused: members missing"
            )
        }
    }
}

// MARK: - GroupMoveFeasibility

/// Whether a whole-group move may proceed.
nonisolated enum GroupMoveFeasibility: Equatable {
    case allowed
    case refused(GroupMoveRefusal)

    var isAllowed: Bool {
        if case .allowed = self {
            true
        } else {
            false
        }
    }

    var refusal: GroupMoveRefusal? {
        if case let .refused(reason) = self {
            reason
        } else {
            nil
        }
    }
}
