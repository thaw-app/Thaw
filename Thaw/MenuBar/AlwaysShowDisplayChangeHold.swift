//
//  AlwaysShowDisplayChangeHold.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Keeps always-show from revealing on unsettled geometry. It holds from a screen-parameter posting
/// until the display change's run reaches its presentation step, and a settle that changed nothing
/// starts no run, so that settle ends the hold itself. A synchronize asked for while holding runs once
/// the hold ends.
nonisolated struct AlwaysShowDisplayChangeHold: Equatable, Sendable {
    /// A posting arrived and its settle has not published yet.
    private(set) var isAwaitingSettle = false
    /// A changed settle started a run that has not reached its presentation step yet.
    private(set) var isAwaitingRun = false
    private(set) var hasDeferredSync = false

    var isHolding: Bool {
        isAwaitingSettle || isAwaitingRun
    }

    mutating func invalidate() {
        isAwaitingSettle = true
    }

    /// Returns whether to synchronize now.
    mutating func settle(_ change: EnvironmentChange) -> Bool {
        isAwaitingSettle = false
        if change != .none {
            isAwaitingRun = true
        }
        return takeDeferredSync()
    }

    /// The presentation step always synchronizes, because the settled bar can change the answer.
    /// It returns false only when a newer posting holds again, which keeps the sync for that run.
    mutating func finishRun() -> Bool {
        isAwaitingRun = false
        hasDeferredSync = true
        return takeDeferredSync()
    }

    /// Returns whether to synchronize now; while holding, the request waits for the hold to end.
    mutating func requestSync() -> Bool {
        hasDeferredSync = true
        return takeDeferredSync()
    }

    private mutating func takeDeferredSync() -> Bool {
        guard !isHolding, hasDeferredSync else { return false }
        hasDeferredSync = false
        return true
    }
}
