//
//  LayoutMoveSequenceExecution.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Executes a planned sequence one verified move at a time, without I/O.
///
/// Call next() to resolve a move against live geometry and
/// confirmLastMove() only after the move verifies. Requesting another move
/// without confirmation counts the previous move as skipped. A skipped move
/// must not become an anchor for later moves.
public struct LayoutMoveSequenceExecution: Sendable {
    public typealias Move = LayoutMoveSequencePlanner.LCSPlannedMove

    private var remaining: ArraySlice<Move>
    private var unverifiedMoverUIDs: Set<String>
    private var awaitingConfirmation: String?

    /// Whether a skipped or failed move requires a fresh plan after draining
    /// the independent moves. An exhausted queue is not necessarily success.
    public private(set) var needsReplan = false

    /// All planned moves verified, with none skipped or invalidated.
    public var isComplete: Bool {
        remaining.isEmpty && awaitingConfirmation == nil && !needsReplan
    }

    public init(moves: [Move]) {
        remaining = moves[...]
        unverifiedMoverUIDs = Set(moves.map(\.uid))
    }

    /// Returns the next move, treating any unconfirmed predecessor as skipped.
    public mutating func next() -> Move? {
        if awaitingConfirmation != nil {
            needsReplan = true
            awaitingConfirmation = nil
        }
        while let move = remaining.popFirst() {
            switch move.destination {
            case let .leftOfUID(uid), let .rightOfUID(uid):
                if unverifiedMoverUIDs.contains(uid) {
                    // Leave this mover unverified too, invalidating transitive
                    // dependencies without discarding independent moves.
                    needsReplan = true
                    continue
                }
            case .sectionBoundary:
                break
            }
            awaitingConfirmation = move.uid
            return move
        }
        return nil
    }

    /// Confirms that the last returned move reached its destination.
    public mutating func confirmLastMove() {
        if let awaitingConfirmation {
            unverifiedMoverUIDs.remove(awaitingConfirmation)
        }
        awaitingConfirmation = nil
    }

    /// Discards the remaining plan after a failed drag, which may have moved
    /// items even though it did not verify. Refresh geometry before replanning.
    public mutating func invalidate() {
        remaining.removeAll()
        awaitingConfirmation = nil
        needsReplan = true
    }
}
