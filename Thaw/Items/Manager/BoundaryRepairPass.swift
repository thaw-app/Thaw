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
    /// Strands one pass may pick before it gives up.
    static let strandBudget = 6

    private(set) var attempted: [MenuBarItem] = []
    private(set) var turns = 0
    private var attemptedIDs = Set<String>()
    private var skippedIDs = Set<String>()

    func next(in strands: [MenuBarItem]) -> MenuBarItem? {
        strands.first { !attemptedIDs.contains($0.uniqueIdentifier) && !skippedIDs.contains($0.uniqueIdentifier) }
    }

    /// Counts a pick; false once the pass has spent its budget.
    mutating func takeTurn() -> Bool {
        turns += 1
        return turns <= Self.strandBudget
    }

    mutating func recordAttempt(_ item: MenuBarItem) {
        if attemptedIDs.insert(item.uniqueIdentifier).inserted {
            attempted.append(item)
        }
    }

    /// Takes a strand the repair must not move out of this pass. It is not
    /// scored, and on its own it does not ask for another pass.
    mutating func skip(_ item: MenuBarItem) {
        skippedIDs.insert(item.uniqueIdentifier)
    }

    func needsRetry(in strands: [MenuBarItem]) -> Bool {
        // Exhausting this pass's attempts is not evidence that the bar is
        // repaired. The caller has already removed cleared/suppressed items.
        !attempted.isEmpty && strands.contains { !skippedIDs.contains($0.uniqueIdentifier) }
    }
}
