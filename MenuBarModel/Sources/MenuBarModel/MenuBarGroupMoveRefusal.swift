//
//  MenuBarGroupMoveRefusal.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Why a whole-group section move was refused.
///
/// A group is indivisible, so a move that cannot apply to every member must not
/// apply to any of them. Carrying the offending item rather than a bare bool
/// is what lets the UI name the app that blocked the move; a raw identifier like
/// com.bjango.istatmenus.status:Battery is not a user-facing string.
public enum MenuBarGroupMoveRefusal: Equatable, Sendable {
    /// An item the app must never reassign.
    case protectedMember(item: MenuBarItem)
    /// An item macOS declines to conceal.
    case hidingUnsupported(item: MenuBarItem)
    /// An item that cannot be hidden in its current state.
    case notHideable(item: MenuBarItem)
    /// Hiding is unavailable on this OS altogether.
    case hidingUnavailable
    /// Some members are not on the bar, so the group cannot move as a unit.
    case unresolvedMembers(missingCount: Int)

    /// The item that blocked the move, when one item is to blame.
    public var blockingItem: MenuBarItem? {
        switch self {
        case let .protectedMember(item),
             let .hidingUnsupported(item),
             let .notHideable(item):
            item
        case .hidingUnavailable, .unresolvedMembers:
            nil
        }
    }
}
