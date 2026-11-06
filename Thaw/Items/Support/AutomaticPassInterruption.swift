//
//  AutomaticPassInterruption.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Which automatic passes the user's input called off: those asked for in an epoch before the latest input.
/// A pass the user's own action asked for, such as the normalization after a ⌘-drag, moves to the new epoch and keeps its turn.
nonisolated struct AutomaticPassInterruption {
    typealias Work = RepairOrchestrator.Work

    private struct Stamp {
        var epoch: UInt64
        let byUser: Bool
    }

    private var epoch: UInt64 = 0
    private var stamps = [Work: Stamp]()
    /// Passes in the lane, with the stamp their request carried when they started.
    private var running = [Work: Stamp]()

    /// Stamps a request with the current epoch.
    mutating func noteRequest(_ work: Work, byUser: Bool) {
        let keepsUserStamp = stamps[work].map { $0.byUser && $0.epoch == epoch } ?? false
        stamps[work] = Stamp(epoch: epoch, byUser: byUser || keepsUserStamp)
    }

    /// Opens a new epoch and returns the automatic work it called off.
    @discardableResult
    mutating func noteUserInput() -> [Work] {
        let previous = epoch
        epoch &+= 1
        var calledOff = [Work]()
        for (work, stamp) in stamps {
            if stamp.byUser {
                stamps[work]?.epoch = epoch
            } else if stamp.epoch == previous {
                calledOff.append(work)
            }
        }
        for (work, stamp) in running where stamp.byUser {
            running[work]?.epoch = epoch
        }
        return calledOff.sorted { $0.rawValue < $1.rawValue }
    }

    /// Whether the pass for this work was asked for before the latest user input.
    func isCalledOff(_ work: Work) -> Bool {
        stamps[work].map { $0.epoch < epoch } ?? false
    }

    /// Records an automatic pass taking the lane, in the epoch it was asked for.
    /// The pass uses up its request, so a later request starts from a stamp of its own.
    mutating func noteStarted(_ work: Work) {
        running[work] = stamps.removeValue(forKey: work) ?? Stamp(epoch: epoch, byUser: false)
    }

    /// Whether user input arrived after this automatic pass started.
    func isInterrupted(_ work: Work) -> Bool {
        running[work].map { $0.epoch < epoch } ?? false
    }

    mutating func noteFinished(_ work: Work) {
        running[work] = nil
    }

    /// Forgets the request of work that was withdrawn, so it cannot call off a later one.
    mutating func forget(_ work: Work) {
        stamps[work] = nil
    }
}
