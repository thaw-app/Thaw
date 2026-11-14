//
//  SectionDragSkip.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Why a planned section-order drag is skipped, and whether the skip ends the
/// whole move loop rather than just this move.
///
/// The checks run in a fixed order and the first one that fires wins, so a move
/// that trips two of them is skipped for the earlier one. The caller reads the
/// bar and the failure memory into Inputs, and keeps the logging and the
/// failure-key writes, so each skip is recorded exactly once.
struct SectionDragSkip: Equatable {
    enum Reason: Equatable {
        case parked
        case circuitBreaker
        case hidingUnsupported
        case agentOwned
        case recentlyFailed
    }

    /// What the checks need to know about one planned move.
    struct Inputs {
        /// The item sits off the menu bar band. Only asked on a first pass, so
        /// the caller passes false on a repair pass.
        var isParked = false
        var isUserInitiated = false
        /// The item-scoped breaker has tripped for this item, side and target.
        var breakerTripped = false
        /// The item or the target is on the hiding-unsupported denylist.
        var hidingUnsupported = false
        /// The item is composited by MenuBarAgent itself.
        var agentOwned = false
        /// The same move failed under this desired order inside the backoff window.
        var backingOff = false
        /// The pass follows a plan, so a skipped move only skips itself.
        var usesPlan = false
    }

    let reason: Reason
    let endsMoveLoop: Bool

    /// The first check that fires for these inputs, or nil when the drag may go ahead.
    static func firstReason(for inputs: Inputs) -> SectionDragSkip? {
        // A parked item ends the loop whatever the pass: the order is deferred.
        if inputs.isParked {
            return SectionDragSkip(reason: .parked, endsMoveLoop: true)
        }
        // User passes are exempt from the breaker.
        if !inputs.isUserInitiated, inputs.breakerTripped {
            return SectionDragSkip(reason: .circuitBreaker, endsMoveLoop: !inputs.usesPlan)
        }
        if inputs.hidingUnsupported {
            return SectionDragSkip(reason: .hidingUnsupported, endsMoveLoop: !inputs.usesPlan)
        }
        if inputs.agentOwned {
            return SectionDragSkip(reason: .agentOwned, endsMoveLoop: !inputs.usesPlan)
        }
        // Repair passes are included: two failures already covered the retry.
        if inputs.backingOff {
            return SectionDragSkip(reason: .recentlyFailed, endsMoveLoop: !inputs.usesPlan)
        }
        return nil
    }
}
