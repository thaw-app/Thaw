//
//  MenuBarItemManager+BulkApplyGating.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

extension MenuBarItemManager {
    /// Tracks which move timestamp belongs to a multi-item automatic apply.
    ///
    /// After each move the batch adopts the timestamp it saw while holding
    /// moveGate, so it accepts its own moves and rejects a user move in between.
    nonisolated struct BatchMovePreflightState {
        private var didFinishMove = false
        private var expectedTimestamp: ContinuousClock.Instant?

        func shouldBeginMove(
            currentTimestamp: ContinuousClock.Instant?,
            initialPreflight: () -> Bool
        ) -> Bool {
            guard didFinishMove else {
                return initialPreflight()
            }
            return currentTimestamp == expectedTimestamp
        }

        mutating func recordMoveGateExit(timestamp: ContinuousClock.Instant?) {
            didFinishMove = true
            expectedTimestamp = timestamp
        }
    }

    /// Authority of a bulk layout request. Higher-authority work may replace
    /// lower-authority work; lower-authority background work never displaces a
    /// profile the user explicitly selected.
    nonisolated enum LayoutBatchKind: Int, Equatable {
        case savedRestore
        case profileResort
        case explicitProfile
    }

    nonisolated struct LayoutBatchLease: Equatable {
        let generation: UInt
        let kind: LayoutBatchKind
    }

    static nonisolated func layoutBatchMaySupersede(
        active: LayoutBatchKind?,
        requested: LayoutBatchKind
    ) -> Bool {
        guard let active else { return true }
        return requested.rawValue >= active.rawValue
    }

    /// Claims ownership for a batch and invalidates any lower-authority work.
    @discardableResult
    func beginLayoutBatch(_ kind: LayoutBatchKind) -> LayoutBatchLease? {
        guard Self.layoutBatchMaySupersede(
            active: activeLayoutBatchLease?.kind,
            requested: kind
        ) else {
            MenuBarItemManager.diagLog.debug(
                "Layout batch \(kind) deferred behind \(String(describing: activeLayoutBatchLease?.kind))"
            )
            return nil
        }

        if kind == .explicitProfile {
            profileResortTask?.cancel()
            profileResortTask = nil
        }
        layoutBatchGeneration &+= 1
        let lease = LayoutBatchLease(generation: layoutBatchGeneration, kind: kind)
        activeLayoutBatchLease = lease
        return lease
    }

    func layoutBatchIsCurrent(_ lease: LayoutBatchLease) -> Bool {
        activeLayoutBatchLease == lease && layoutBatchGeneration == lease.generation
    }

    func finishLayoutBatch(_ lease: LayoutBatchLease) {
        guard layoutBatchIsCurrent(lease) else { return }
        activeLayoutBatchLease = nil
    }

    func cancelActiveLayoutBatch(ifKind kind: LayoutBatchKind) {
        guard activeLayoutBatchLease?.kind == kind else { return }
        layoutBatchGeneration &+= 1
        activeLayoutBatchLease = nil
    }

    /// Whether a bulk apply that left moves unenacted should still hold
    /// the saveSectionOrder gate shut.
    ///
    /// Never expires, or the failed batch gets saved (#900). A clean apply or a
    /// user move clears it.
    static nonisolated func unfinishedMoveBatchBlocksSave(
        observedAt: ContinuousClock.Instant?
    ) -> Bool {
        observedAt != nil
    }

    /// The idle window an automatic bulk apply should wait for, or nil
    /// when the gate is switched off.
    ///
    /// A non-positive threshold switches it off. A negative cap is clamped so a
    /// defaults typo means "don't wait", not "never start".
    static nonisolated func bulkApplyIdleWindow(
        thresholdMs: Int,
        capMs: Int
    ) -> (threshold: Duration, cap: Duration)? {
        guard thresholdMs > 0 else { return nil }
        return (.milliseconds(thresholdMs), .milliseconds(max(0, capMs)))
    }

    nonisolated enum BulkApplyIdleWaitDecision: Equatable {
        case waiting
        case ready
        case deferBatch
    }

    /// Whether an automatic bulk apply may start, must keep waiting, or should
    /// defer this dispatch. The cap is never permission to override input.
    static nonisolated func bulkApplyIdleWaitDecision(
        userHasPausedInput: Bool,
        elapsed: Duration,
        cap: Duration
    ) -> BulkApplyIdleWaitDecision {
        if userHasPausedInput {
            return .ready
        }
        if elapsed >= cap {
            return .deferBatch
        }
        return .waiting
    }

    /// Batches yield only between complete gestures, after the previous mouse-up.
    static nonisolated func automaticBatchShouldYieldForInput(
        automatic: Bool,
        userHasPausedPhysicalInput: Bool
    ) -> Bool {
        automatic && !userHasPausedPhysicalInput
    }
}
