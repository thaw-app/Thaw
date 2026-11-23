//
//  LeadingEdgeFollowers.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Who follows the menu bar's leading edge. The edge watcher polls only while
/// someone does, so a bar whose shape is not drawn around the items asks no
/// app for its position.
nonisolated struct LeadingEdgeFollowers {
    /// What the watcher has to do after a follower comes or goes.
    enum Transition: Equatable {
        case none
        /// The first follower arrived: start polling.
        case start
        /// The last follower left: stop polling.
        case stop
    }

    private var ids = Set<UUID>()

    var isFollowed: Bool {
        !ids.isEmpty
    }

    /// Adds a follower. Adding one that is already following changes nothing.
    mutating func add(_ id: UUID) -> Transition {
        let wasFollowed = isFollowed
        guard ids.insert(id).inserted else { return .none }
        return wasFollowed ? .none : .start
    }

    /// Removes a follower. Removing one twice, or one never added, changes
    /// nothing, so a token released more than once cannot stop polling for
    /// the others.
    mutating func remove(_ id: UUID) -> Transition {
        guard ids.remove(id) != nil else { return .none }
        return isFollowed ? .none : .stop
    }
}
