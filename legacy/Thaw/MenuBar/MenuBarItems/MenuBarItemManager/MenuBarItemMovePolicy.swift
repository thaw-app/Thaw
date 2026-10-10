//
//  MenuBarItemMovePolicy.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

// MARK: - Move Policy

extension MenuBarItemManager {
    /// The pure core of `move(item:to:)`.
    ///
    /// `move` posts events and reads the bar; what it decides lives here over
    /// plain values, so a field log's attempts can be replayed in a test.
    ///
    /// Each attempt yields an ``Observation`` that
    /// ``decide(after:state:configuration:)`` folds into ``State``. Stop
    /// reasons are specific because callers report them to the user.
    nonisolated enum MovePolicy {
        /// What one attempt observed.
        nonisolated enum Observation: Equatable {
            /// The item was verified beside the target once the bar settled.
            case landed
            /// The owner answered the press and the release, but the item is
            /// not beside the target. `revertedToStart` records a release that
            /// put it exactly back where it started; `targetMinX` is where the
            /// target sits now.
            case displaced(revertedToStart: Bool, targetMinX: CGFloat?)
            /// The attempt threw before a landing could be judged.
            case failed(AttemptFailure)
        }

        /// Why an attempt threw, reduced to what the policy needs.
        nonisolated enum AttemptFailure: Equatable {
            /// A posted event, or the item's reaction to it, timed out.
            case ownerSilent
            /// The owner is alive but not pumping its event loop.
            case ownerUnresponsive
            /// The item's window no longer reports bounds.
            case itemGone
            /// The destination anchor no longer reports bounds.
            case destinationGone
            /// The target window was recycled or its geometry is unusable, so
            /// retrying would drag against geometry the bar no longer has.
            case staleDestination
            /// The caller's condition changed; the move is obsolete.
            case superseded
            /// The press outlived its deadline and was released by the guard.
            case overran
            /// The selected endpoints do not form a safe path on one display.
            case unsafePath
            /// Anything else.
            case other
        }

        /// What `move` does next.
        nonisolated enum Decision: Equatable {
            case succeed
            case retry
            case stop(StopReason)
        }

        /// Why a move stopped short of a verified landing.
        nonisolated enum StopReason: Equatable {
            /// Two consecutive releases put the item straight back where it
            /// started: macOS is restoring the item's autosaved slot.
            case refusedByMacOS
            /// The target travelled more than a display width during the drag.
            case targetMoved
            /// The target retreated in one direction on every recent attempt.
            case targetRetreating
            /// The owner is hung; no event will be acknowledged this call.
            case ownerUnresponsive
            /// The owner has a standing record of ignoring events and just
            /// did so again.
            case ownerAlwaysSilent
            /// Events timed out on the final attempt.
            case ownerSilent
            case itemGone
            case destinationGone
            /// The destination anchor no longer matches the plan (recycled
            /// target window or unusable endpoint geometry).
            case staleDestination
            case superseded
            /// A press was released by the deadline guard, or the move as a
            /// whole ran past its deadline.
            case overran
            /// No transport can safely connect the selected endpoints.
            case unsafePath
            /// Every attempt displaced the item without landing it.
            case budgetExhausted
            /// The final attempt failed for an unclassified reason.
            case other

            /// Whether the item could still be at the destination, so the bar
            /// must be checked before reporting a failure.
            var deservesFinalLandingCheck: Bool {
                switch self {
                case .targetMoved, .targetRetreating, .ownerAlwaysSilent, .ownerSilent, .overran, .budgetExhausted, .other:
                    true
                case .refusedByMacOS, .ownerUnresponsive, .itemGone, .destinationGone, .staleDestination, .superseded, .unsafePath:
                    false
                }
            }

            /// Whether the failure is filed against the item's owner in the
            /// failure ledger. Only silence is: a refused drop, a moved target,
            /// and a deadline overrun say nothing about the owner.
            var isFiledAgainstOwner: Bool {
                switch self {
                case .ownerUnresponsive, .ownerAlwaysSilent, .ownerSilent:
                    true
                case .refusedByMacOS, .targetMoved, .targetRetreating, .itemGone, .destinationGone, .staleDestination, .superseded, .overran, .unsafePath, .budgetExhausted, .other:
                    false
                }
            }

            var logString: String {
                switch self {
                case .refusedByMacOS: "refused by macOS"
                case .targetMoved: "target moved"
                case .targetRetreating: "target retreating"
                case .ownerUnresponsive: "owner unresponsive"
                case .ownerAlwaysSilent: "owner always silent"
                case .ownerSilent: "owner silent"
                case .itemGone: "item gone"
                case .destinationGone: "destination gone"
                case .staleDestination: "stale destination"
                case .superseded: "superseded"
                case .overran: "overran deadline"
                case .unsafePath: "unsafe path"
                case .budgetExhausted: "budget exhausted"
                case .other: "other"
                }
            }
        }

        /// The fixed inputs of one move.
        nonisolated struct Configuration: Equatable {
            /// How many attempts the move may spend.
            var maxAttempts: Int
            /// The width of the display the move runs on; the staleness
            /// threshold for a target that moved.
            var displayWidth: CGFloat
            /// Whether the moved item is a zero-width control item, whose
            /// position match can coincide with bounds drifting externally.
            var itemIsControlItem: Bool
            /// Whether the failure ledger holds a standing unresponsive mark
            /// for the item's owner.
            var ownerHasSilentRecord: Bool
            /// Consecutive reverted releases that prove a refusal.
            var revertRunLength = 2
            /// Consecutive same-direction target moves that prove a retreat.
            var retreatRunLength = 3
        }

        /// The running state of one move across attempts.
        nonisolated struct State: Equatable {
            /// Attempts observed so far.
            var attempts = 0
            /// Consecutive attempts whose release put the item back at its start.
            var revertedRun = 0
            /// Whether any attempt's events displaced the item at all.
            var anyEventsSucceeded = false
            /// The target's `minX` when the move was planned, then at the end
            /// of every attempt that observed it.
            var targetMinXHistory: [CGFloat]

            init(plannedTargetMinX: CGFloat?) {
                targetMinXHistory = plannedTargetMinX.map { [$0] } ?? []
            }

            /// Where the target sat when the move was planned.
            var plannedTargetMinX: CGFloat? {
                targetMinXHistory.first
            }

            /// Where the target sat after the most recent attempt.
            var latestTargetMinX: CGFloat? {
                targetMinXHistory.count > 1 ? targetMinXHistory.last : nil
            }
        }

        /// Folds one attempt's observation into `state` and decides what
        /// `move` does next.
        ///
        /// Check order matters: refusal (two reverted releases), then a moved
        /// target, then a retreat, and only then the attempt budget.
        static func decide(
            after observation: Observation,
            state: inout State,
            configuration: Configuration
        ) -> Decision {
            state.attempts += 1
            let maxAttempts = max(1, configuration.maxAttempts)

            switch observation {
            case .landed:
                state.anyEventsSucceeded = true
                return .succeed

            case let .displaced(revertedToStart, targetMinX):
                state.anyEventsSucceeded = true
                if revertedToStart {
                    state.revertedRun += 1
                    if state.revertedRun >= max(1, configuration.revertRunLength) {
                        return .stop(.refusedByMacOS)
                    }
                } else {
                    state.revertedRun = 0
                }
                if let targetMinX {
                    state.targetMinXHistory.append(targetMinX)
                }
                if let planned = state.plannedTargetMinX,
                   let targetMinX,
                   destinationIsStale(
                       plannedTargetMinX: planned,
                       currentTargetMinX: targetMinX,
                       displayWidth: configuration.displayWidth
                   )
                {
                    return .stop(.targetMoved)
                }
                if targetIsRetreating(
                    recentTargetMinX: state.targetMinXHistory,
                    runLength: configuration.retreatRunLength
                ) {
                    return .stop(.targetRetreating)
                }
                return state.attempts < maxAttempts ? .retry : .stop(.budgetExhausted)

            case let .failed(failure):
                switch failure {
                case .itemGone:
                    return .stop(.itemGone)
                case .destinationGone:
                    return .stop(.destinationGone)
                case .staleDestination:
                    return .stop(.staleDestination)
                case .ownerUnresponsive:
                    return .stop(.ownerUnresponsive)
                case .superseded:
                    return .stop(.superseded)
                case .overran:
                    return .stop(.overran)
                case .unsafePath:
                    return .stop(.unsafePath)
                case .ownerSilent:
                    // Stop only on silence, not up front: an owner that
                    // responds without landing still gets its full budget.
                    if configuration.ownerHasSilentRecord {
                        return .stop(.ownerAlwaysSilent)
                    }
                    return state.attempts < maxAttempts ? .retry : .stop(.ownerSilent)
                case .other:
                    return state.attempts < maxAttempts ? .retry : .stop(.other)
                }
            }
        }

        /// Whether a position match read *before* posting an attempt's events
        /// can be trusted as a landing.
        ///
        /// On retries, a zero-width control item's bounds may have drifted onto
        /// the target, so those need observed displacement.
        static func trustsPositionMatch(
            attempt: Int,
            anyEventsSucceeded: Bool,
            itemIsControlItem: Bool
        ) -> Bool {
            attempt <= 1 || anyEventsSucceeded || !itemIsControlItem
        }

        /// Whether a move that has been running for `elapsed` may start
        /// another attempt.
        ///
        /// Bounded attempts still add up; yield before the cursor watchdog and
        /// move-gate waiters give up.
        static func mayStartAnotherAttempt(elapsed: Duration, deadline: Duration) -> Bool {
            elapsed < deadline
        }

        /// Maps an error thrown before posting, kept beside
        /// ``decide(after:state:configuration:)``.
        static func attemptFailure(for error: EventError) -> AttemptFailure {
            switch error {
            case .eventOperationTimeout, .itemResponseTimeout:
                .ownerSilent
            case .ownerUnresponsive:
                .ownerUnresponsive
            case .missingItemBounds:
                .itemGone
            case .missingDestinationBounds:
                .destinationGone
            case .moveSuperseded:
                .superseded
            case .moveTimedOut:
                .overran
            case .unsafeMovePath:
                .unsafePath
            case .staleDestination:
                .staleDestination
            case .cannotComplete, .invalidEventSource, .missingMouseLocation, .eventCreationFailure,
                 .itemNotMovable, .menuTrackingActive, .eventWindowMismatch,
                 .inputPauseTimedOut, .dropReverted, .moveEngineBusy:
                .other
            }
        }
    }

    // MARK: - Failure attribution

    /// How the failure ledger should file a move error against the item.
    ///
    /// The unresponsive mark is for an app that ignores synthetic events
    /// (Little Snitch without GUI Scripting). On macOS 26 hosted items'
    /// events reach Control Center, whose timeouts say nothing about the app,
    /// so only file it when events reach the item's own app.
    ///
    /// Never mark a provisional identity: its key changes on resolution.
    static nonisolated func ledgerFailureKind(
        for error: EventError,
        ownerIsControlCenter: Bool,
        hasProvisionalIdentity: Bool
    ) -> MenuBarItemFailureLedger.FailureKind {
        switch error {
        case .ownerUnresponsive, .eventOperationTimeout, .itemResponseTimeout:
            return ownerIsControlCenter || hasProvisionalIdentity ? .other : .unresponsiveOwner
        case .cannotComplete, .invalidEventSource, .missingMouseLocation, .eventCreationFailure,
             .itemNotMovable, .missingItemBounds, .missingDestinationBounds, .menuTrackingActive, .eventWindowMismatch,
             .staleDestination, .inputPauseTimedOut, .moveSuperseded, .dropReverted,
             .moveEngineBusy, .moveTimedOut, .unsafeMovePath:
            return .other
        }
    }

    // MARK: - Refused moves

    /// How long macOS's refusal of a move keeps the item's saved slot from
    /// being overwritten by wherever the refusal left it.
    ///
    /// Observed refusals cleared by themselves within minutes; a landing
    /// clears the record sooner.
    static nonisolated let refusedMoveLifetime: Duration = .seconds(10 * 60)

    /// Whether a recorded refusal still stands.
    static nonisolated func refusedMoveIsCurrent(
        recordedAt: ContinuousClock.Instant,
        now: ContinuousClock.Instant,
        lifetime: Duration = refusedMoveLifetime
    ) -> Bool {
        now - recordedAt < lifetime
    }

    /// Records that macOS put `item` straight back after every release. While
    /// the record stands, saved-order persistence keeps the intended slot
    /// instead of adopting the position left by the refusal.
    func noteRefusedMove(of item: MenuBarItem) {
        macOSRefusedMoves[item.uniqueIdentifier] = .now
    }

    /// Forgets a refusal because the item just landed.
    func clearRefusedMove(of item: MenuBarItem) {
        macOSRefusedMoves[item.uniqueIdentifier] = nil
    }

    /// The identifiers whose most recent move macOS refused, with expired
    /// records dropped on the way out.
    func refusedMoveIdentifiers(now: ContinuousClock.Instant = .now) -> Set<String> {
        macOSRefusedMoves = macOSRefusedMoves.filter { entry in
            Self.refusedMoveIsCurrent(recordedAt: entry.value, now: now)
        }
        return Set(macOSRefusedMoves.keys)
    }

    /// The error a stopped move throws, so callers receive a precise outcome.
    static nonisolated func moveError(
        for reason: MovePolicy.StopReason,
        item: MenuBarItem,
        destinationItem: MenuBarItem? = nil,
        lastError: (any Error)?
    ) -> any Error {
        switch reason {
        case .refusedByMacOS:
            EventError.dropReverted(item)
        case .targetMoved, .targetRetreating:
            EventError.staleDestination(item)
        case .ownerUnresponsive:
            EventError.ownerUnresponsive(item)
        case .itemGone:
            EventError.missingItemBounds(item)
        case .destinationGone:
            EventError.missingDestinationBounds(destinationItem ?? item)
        case .staleDestination:
            EventError.staleDestination(item)
        case .superseded:
            EventError.moveSuperseded(item)
        case .overran:
            EventError.moveTimedOut(item)
        case .unsafePath:
            EventError.unsafeMovePath(item)
        case .ownerAlwaysSilent, .ownerSilent, .other:
            (lastError as? EventError) ?? EventError.cannotComplete
        case .budgetExhausted:
            EventError.cannotComplete
        }
    }
}
