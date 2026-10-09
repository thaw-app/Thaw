//
//  MoveOperationTracker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Tracks when the menu bar layout was last disturbed by a move operation, so
/// capture and snapshot paths can refuse to act on a bar that is still settling.
///
/// The move engine is the writer; read-only consumers hold the tracker itself
/// rather than reaching through the manager that owns it. Lives in
/// MenuBarModel because both sides of the engine/frontend split need it.
@MainActor
public final class MoveOperationTracker {
    private var lastTimestamp: ContinuousClock.Instant?
    private var inFlightCount = 0

    public init() {}

    /// Records that a move operation just disturbed the bar.
    public func noteMoveOperation() {
        lastTimestamp = .now
    }

    /// Marks the start of a move operation. Until the matching endMoveOperation()
    /// the bar counts as disturbed for every occurred(within:) reader, so capture
    /// and snapshot paths stay out of the way for the whole move, which can take
    /// seconds. Concurrent bar walks during that span slow the move's own walks.
    public func beginMoveOperation() {
        inFlightCount += 1
    }

    /// Balances beginMoveOperation(). Does not stamp: whether the bar was
    /// actually disturbed is recorded by noteMoveOperation() at the
    /// points where it was.
    public func endMoveOperation() {
        inFlightCount = max(0, inFlightCount - 1)
    }

    /// Whether a move operation is currently between its begin and end marks.
    public var isInFlight: Bool {
        inFlightCount > 0
    }

    /// Returns once no move is in flight, or when the task is cancelled.
    public func waitUntilIdle(pollingEvery interval: Duration = .milliseconds(100)) async {
        while isInFlight, !Task.isCancelled {
            try? await Task.sleep(for: interval)
        }
    }

    /// The instant of the most recent move operation, for callers computing
    /// custom buffers off it.
    public var lastInstant: ContinuousClock.Instant? {
        lastTimestamp
    }

    /// Whether the bar was disturbed within the last duration, or a move is
    /// in flight right now.
    public func occurred(within duration: Duration) -> Bool {
        if inFlightCount > 0 {
            return true
        }
        guard let lastTimestamp else {
            return false
        }
        return lastTimestamp.duration(to: .now) <= duration
    }
}
