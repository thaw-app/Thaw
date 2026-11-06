//
//  PostRestrictionRepairItemID.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Darwin
import MenuBarModel

/// The identity the post-restriction and boundary repairs remember an item by.
///
/// An item that relaunches under a new process is a different item to the repairs, so what
/// they gave up on before the relaunch does not carry over.
nonisolated struct PostRestrictionRepairItemID: Hashable {
    let uniqueIdentifier: String
    let ownerPID: pid_t

    init(_ item: MenuBarItem) {
        uniqueIdentifier = item.uniqueIdentifier
        ownerPID = item.ownerPID
    }
}
