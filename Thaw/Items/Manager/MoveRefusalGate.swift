//
//  MoveRefusalGate.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Pure move policy: snapshot live state into Request to get the first reason a move is refused, or nil to go ahead.
///
/// The checks run in a fixed order and the first one that fires wins. The caller keeps the logging, the
/// memory of unresponsive owners and the choice between a quiet no-op and a thrown error, so each refusal
/// is recorded exactly once.
nonisolated enum MoveRefusalGate {
    /// Everything the checks read, snapshotted by the caller.
    nonisolated struct Request {
        /// Manual arrangement refuses every move but an explicit Layout edit, which never reaches this gate.
        let arrangementForbidsMoves: Bool
        /// Whether the screen is locked. Consulted only when manual arrangement did not refuse, because asking
        /// also records the lock transition in the log.
        let isScreenLocked: () -> Bool
        /// Whether the move circuit breaker is open. Consulted only after the lock check.
        let isCircuitBreakerOpen: () -> Bool
        /// A user's own move goes through even while the breaker is open.
        let isUserInitiated: Bool
        let isSystemClone: Bool
        /// The item or the target is the native overflow chevron.
        let involvesNativeOverflowControl: Bool
        let isPositionStoreRecovery: Bool
        let hasAppState: Bool
        let isPhysicallyOrderable: Bool
        let isUserDraggingItem: Bool
        /// Whether the owning app is hung. Consulted last but two, and only for items of other apps, because
        /// asking also updates the memory of unresponsive owners.
        let isOwnerUnresponsive: () -> Bool
        /// Section transitions opt in to a divider target, using the divider as a visible drag anchor.
        let allowsSectionBoundaryTarget: Bool
        /// The target is a control item other than the visible one.
        let targetsLegacyDivider: Bool
    }

    /// Refusals in evaluation order.
    nonisolated enum Rejection: Equatable {
        /// No-ops: the caller treats each as a move that quietly did nothing.
        case manualArrangement
        /// A move under the lock screen lands on a layout the unlock replaces. A no-op false is the one
        /// outcome no caller persists as a verdict.
        case screenLocked
        /// Runaway guard: automatic passes stop, a user's own move still goes through, because it is one
        /// deliberate action, not a storm, and it is how the user retries.
        case circuitBreakerOpen
        /// Dragging a transient system clone displaces real items, and it vanishes on its own.
        case systemClone
        /// The native chevron has no window to grab and no weight the agent honours.
        case nativeOverflowControl
        /// A store recovery is a preference key with a synthetic window ID: nothing to grab, and only an
        /// invented frame to verify against.
        case positionStoreRecovery
        /// Throws: the caller learns the move did not happen.
        case appStateUnavailable
        case itemNotMovable
        /// Overlapping drags strand or duplicate icons and can crash Finder. The drop re-runs this work later.
        case userDragInProgress
        case ownerUnresponsive
        /// A no-op again: the legacy divider hide-move relied on a reflow macOS 27 no longer does.
        case legacyDividerTarget
    }

    /// The first refusing check, or nil when the move may go ahead.
    static nonisolated func firstRejection(_ request: Request) -> Rejection? {
        firstNoOpRejection(request) ?? firstThrowingRejection(request)
    }

    /// The checks that end in a quiet no-op, up to the first that throws.
    private static nonisolated func firstNoOpRejection(_ request: Request) -> Rejection? {
        if request.arrangementForbidsMoves {
            return .manualArrangement
        }
        if request.isScreenLocked() {
            return .screenLocked
        }
        if request.isCircuitBreakerOpen(), !request.isUserInitiated {
            return .circuitBreakerOpen
        }
        if request.isSystemClone {
            return .systemClone
        }
        if request.involvesNativeOverflowControl {
            return .nativeOverflowControl
        }
        if request.isPositionStoreRecovery {
            return .positionStoreRecovery
        }
        return nil
    }

    /// The checks that throw, then the divider check, which is a no-op again.
    private static nonisolated func firstThrowingRejection(_ request: Request) -> Rejection? {
        if !request.hasAppState {
            return .appStateUnavailable
        }
        if !request.isPhysicallyOrderable {
            return .itemNotMovable
        }
        if request.isUserDraggingItem {
            return .userDragInProgress
        }
        if request.isOwnerUnresponsive() {
            return .ownerUnresponsive
        }
        if !request.allowsSectionBoundaryTarget, request.targetsLegacyDivider {
            return .legacyDividerTarget
        }
        return nil
    }
}
