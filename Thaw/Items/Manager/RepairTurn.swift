//
//  RepairTurn.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Runs a repair pass on the repair lane, reading the bar before taking it.
/// The read can queue for seconds behind other accessibility walks, and no other writer should wait on that.
@MainActor
enum RepairTurn {
    /// A reading older than this at admission is dropped: the bar may have changed on its own.
    static nonisolated let readStaleAfter: Duration = .milliseconds(500)

    /// Reads the bar, then waits for the lane. The reading comes back nil when it can no longer be
    /// planned from: it waited too long, or a writer finished after the read began and changed the bar it
    /// describes. Nil overall means the task was cancelled while it queued.
    private static func admit<Reading>(
        _ work: RepairOrchestrator.Work,
        priority: RepairLane.Priority,
        on repairs: RepairOrchestrator,
        readStaleAfter: Duration,
        read: () async -> Reading?
    ) async -> (hold: RepairLane.Hold, reading: Reading?)? {
        let plannedAt = repairs.writeGeneration
        let reading = await read()
        let readAt = ContinuousClock.now
        guard let hold = await repairs.enter(work, priority: priority) else { return nil }
        let isCurrent = repairs.writeGeneration == plannedAt && readAt.duration(to: .now) <= readStaleAfter
        return (hold, isCurrent ? reading : nil)
    }

    /// `write` gets nil when the reading went stale, by time or because another writer finished, and must be taken again.
    /// Returns nil when the task was cancelled while it queued.
    static func run<Reading, Outcome>(
        _ work: RepairOrchestrator.Work,
        priority: RepairLane.Priority = .automatic,
        on repairs: RepairOrchestrator,
        readStaleAfter: Duration = RepairTurn.readStaleAfter,
        read: () async -> Reading?,
        write: (Reading?, borrowing StoreWritePermit) async -> Outcome
    ) async -> Outcome? {
        guard let (hold, reading) = await admit(work, priority: priority, on: repairs, readStaleAfter: readStaleAfter, read: read) else {
            return nil
        }
        let outcome = await write(reading, StoreWritePermit(hold))
        repairs.leave(hold)
        return outcome
    }

    /// The same turn for a pass that ends by checking its own work. `write` also gets its time in the lane:
    /// it asks between writes whether the user is waiting, and hands the permit back once nothing is left to write.
    static func run<Reading, Outcome>(
        _ work: RepairOrchestrator.Work,
        priority: RepairLane.Priority = .automatic,
        on repairs: RepairOrchestrator,
        readStaleAfter: Duration = RepairTurn.readStaleAfter,
        read: () async -> Reading?,
        write: (Reading?, consuming StoreWritePermit, Writing) async -> Outcome
    ) async -> Outcome? {
        guard let (hold, reading) = await admit(work, priority: priority, on: repairs, readStaleAfter: readStaleAfter, read: read) else {
            return nil
        }
        let writing = Writing(hold: hold, repairs: repairs)
        let outcome = await write(reading, StoreWritePermit(hold), writing)
        writing.end()
        return outcome
    }

    /// What a pass still owes once its turn is over. A pass that cannot hand its permit back early
    /// records the read it would have ended with here, and its caller makes that read with the lane free.
    @MainActor
    final class Aftermath {
        /// Set when the pass wrote and the item cache should be read again.
        var needsCachePass = false

        /// Ends a pass with its closing read. A caller that gave an aftermath makes the read after its
        /// turn, with the lane free; without one the read happens here, inside the lane.
        static func closingRead(owedTo aftermath: Aftermath?, _ read: () async -> Void) async {
            guard let aftermath else { return await read() }
            aftermath.needsCachePass = true
        }

        /// Makes the owed cache read, once the turn is over and the lane is free.
        func readCacheIfOwed(_ read: () async -> Void) async {
            guard needsCachePass, !Task.isCancelled else { return }
            needsCachePass = false
            await read()
        }
    }

    /// A pass's time in the lane. It is over when the pass returns, or sooner when it hands its permit back.
    @MainActor
    final class Writing {
        private let hold: RepairLane.Hold
        private let repairs: RepairOrchestrator
        private(set) var isOver = false

        fileprivate init(hold: RepairLane.Hold, repairs: RepairOrchestrator) {
            self.hold = hold
            self.repairs = repairs
        }

        /// Whether something the user asked for is queued behind this pass. Checked between writes;
        /// a pass that finds it true stops writing and leaves the rest to its next run.
        var userWorkIsWaiting: Bool {
            !isOver && repairs.userWorkIsWaiting
        }

        /// Gives the lane to the next pass while this one reads back what it wrote.
        /// Takes the permit, so nothing can be written after.
        func end(_: consuming StoreWritePermit) {
            end()
        }

        fileprivate func end() {
            guard !isOver else { return }
            isOver = true
            repairs.leave(hold)
        }
    }
}
