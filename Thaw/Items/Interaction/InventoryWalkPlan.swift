//
//  InventoryWalkPlan.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import os.lock
import ThawAXCore

/// Which apps an inventory read asks.
///
/// Asking every running app is slow, and nearly all of them have nothing on the menu bar.
/// MenuBarAgent's window says which apps have an item drawn, so between full walks a read asks
/// only those, the apps already known to own items, and any app not asked before. A full walk
/// still runs whenever that shortcut cannot be trusted, and on a timer in case it is wrong in a
/// way nobody has seen yet.
nonisolated struct InventoryWalkPlan: Equatable {
    let scope: MenuBarScanScope
    let priorityOwners: Set<pid_t>

    /// How long the shortcut runs before every app is asked again.
    static let fullWalkInterval = Duration.seconds(60)

    /// - Parameters:
    ///   - requested: Owners the caller needs read whatever the plan.
    ///   - drawnOwners: Apps with an item drawn on the bar, or nil when that could not be read.
    ///   - lastFullWalk: When a walk of every app last finished, or nil if none has.
    static func make(
        requested: Set<pid_t>,
        drawnOwners: Set<pid_t>?,
        lastFullWalk: ContinuousClock.Instant?,
        now: ContinuousClock.Instant = .now
    ) -> InventoryWalkPlan {
        guard let drawnOwners, let lastFullWalk, now - lastFullWalk < fullWalkInterval else {
            return InventoryWalkPlan(scope: .discovery, priorityOwners: requested)
        }
        return InventoryWalkPlan(scope: .settledOwners, priorityOwners: requested.union(drawnOwners))
    }
}

/// When a walk of every app last finished. Read and written from walks off the main actor.
nonisolated final class FullWalkLedger: Sendable {
    private let finishedAt = OSAllocatedUnfairLock<ContinuousClock.Instant?>(initialState: nil)

    var lastFullWalk: ContinuousClock.Instant? {
        finishedAt.withLock { $0 }
    }

    func noteFullWalk(at instant: ContinuousClock.Instant = .now) {
        finishedAt.withLock { $0 = instant }
    }

    /// Makes the next read a full walk.
    func forget() {
        finishedAt.withLock { $0 = nil }
    }
}

/// The last read of MenuBarAgent's window, so a walk can use the read its plan was made from
/// instead of asking the agent again.
nonisolated final class DrawnBarLedger: Sendable {
    struct Reading: Sendable {
        /// The entries when the bar was at rest, or nil when it could not be read or was mid-change.
        let entries: [MenuBarAgentWindow.Entry]?
        let takenAt: ContinuousClock.Instant
    }

    private let latest = OSAllocatedUnfairLock<Reading?>(initialState: nil)

    /// Reads the window, keeps the reading and returns its settled entries.
    func read(
        using source: () -> [MenuBarAgentWindow.Entry]? = { AXPrimitives.menuBarAgentSettledEntries() },
        now: ContinuousClock.Instant = .now
    ) -> [MenuBarAgentWindow.Entry]? {
        let entries = source()
        latest.withLock { $0 = Reading(entries: entries, takenAt: now) }
        return entries
    }

    /// The last reading when it was taken at or after instant.
    func reading(since instant: ContinuousClock.Instant) -> Reading? {
        latest.withLock { reading in
            reading.flatMap { $0.takenAt >= instant ? $0 : nil }
        }
    }
}
