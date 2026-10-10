//
//  BoundaryRepairPass.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Tracks attempts separately from the fresh, unsuppressed strands supplied
/// by the caller. An item may exhaust this pass without being repaired.
struct BoundaryRepairPass {
    private(set) var attempted: [MenuBarItem] = []
    private var attemptedIDs = Set<String>()

    func next(in strands: [MenuBarItem]) -> MenuBarItem? {
        strands.first { !attemptedIDs.contains($0.uniqueIdentifier) }
    }

    mutating func recordAttempt(_ item: MenuBarItem) {
        if attemptedIDs.insert(item.uniqueIdentifier).inserted {
            attempted.append(item)
        }
    }

    func needsRetry(in strands: [MenuBarItem]) -> Bool {
        // Exhausting this pass's attempts is not evidence that the bar is
        // repaired. The caller has already removed cleared/suppressed items.
        !attempted.isEmpty && !strands.isEmpty
    }
}
