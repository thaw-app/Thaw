//
//  SettlingSourcePIDs.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Which cached items the startup settle waits on for a source PID.
nonisolated enum SettlingSourcePIDs {
    /// A concealed item the kit restores from its snapshot has owner PID 0 and never gets a source PID,
    /// so waiting for it would hold the settle until its deadline.
    static func unresolvedCount(in items: [MenuBarItem]) -> Int {
        items.count { $0.sourcePID == nil && $0.ownerPID != 0 }
    }
}
