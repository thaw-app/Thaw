//
//  DragGeometrySource.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Darwin
import MenuBarModel

/// Where a move reads the bar from. The owners already known answer
/// in milliseconds; a full read asks every running app again and can take seconds.
@MainActor
enum DragGeometrySource {
    static func items(
        owners: Set<pid_t> = [],
        fresh: (Set<pid_t>) async -> [MenuBarItem]? = { await MenuBarItem.getFreshMenuBarItemsForMove(priorityPIDs: $0) },
        full: () async -> [MenuBarItem]
    ) async -> [MenuBarItem] {
        if let items = await fresh(owners) {
            return items
        }
        return await full()
    }
}
