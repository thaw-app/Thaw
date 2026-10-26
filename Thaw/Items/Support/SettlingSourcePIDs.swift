//
//  SettlingSourcePIDs.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Which cached items the startup settle waits on for a source PID.
nonisolated enum SettlingSourcePIDs {
    /// Live items still missing a source PID. A concealed item the kit brings back from its saved
    /// snapshot has no process this boot (owner PID 0) and never gets one, so waiting for it would
    /// hold every settle with two such items until its deadline.
    static func unresolvedCount(in items: [MenuBarItem]) -> Int {
        items.count { $0.sourcePID == nil && $0.ownerPID != 0 }
    }
}
