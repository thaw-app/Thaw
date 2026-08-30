//
//  MenuBarItemMovePolicy.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

// MARK: - Move Policy

extension MenuBarItemManager {
    /// The pure core of `move(item:to:)`.
    ///
    /// `move` posts events and reads the bar; everything it *decides* — retry
    /// or stop, and what to call the result — lives here, over plain values,
    /// so a field log's sequence of attempts can be replayed in a unit test
    /// and the verdict the user sees can be checked without a live menu bar.
    ///
    /// Each attempt produces one ``Observation``. ``decide(after:state:configuration:)``
    /// folds it into the running ``State`` and answers with a ``Decision``:
    /// the move landed, another attempt is worth making, or it stops for a
    /// named ``StopReason``. The reasons are deliberately specific, because
    /// the callers report them to the user: a drop that macOS put back is not
    /// an owner that never answered, and neither is a destination that moved.
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
            /// The caller's condition changed; the move is obsolete.
            case superseded
            /// The press outlived its deadline and was released by the guard.
            case overran
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
            case superseded
            /// A press was released by the deadline guard, or the move as a
            /// whole ran past its deadline.
            case overran
            /// Every attempt displaced the item without landing it.
            case budgetExhausted
            /// The final attempt failed for an unclassified reason.
            case other

            /// Whether the item could nevertheless be sitting at the
            /// destination, so the verdict must be checked against the bar
            /// before it is reported as a failure.
            ///
            /// Not for a refused drop, whose releases were observed putting
            /// the item back; not for a vanished item; not for a superseded
            /// move, whose caller no longer wants the answer; and not for a
            /// hung owner, which never received a press.
            var deservesFinalLandingCheck: Bool {
                switch self {
                case .targetMoved, .targetRetreating, .ownerAlwaysSilent, .ownerSilent, .overran, .budgetExhausted, .other:
                    true
                case .refusedByMacOS, .ownerUnresponsive, .itemGone, .destinationGone, .superseded:
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
                case .refusedByMacOS, .targetMoved, .targetRetreating, .itemGone, .destinationGone, .superseded, .overran, .budgetExhausted, .other:
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
                case .superseded: "superseded"
                case .overran: "overran deadline"
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
        /// Order of the checks on a displaced item matters and mirrors the
        /// evidence each one needs: a refusal is proven by the releases alone
        /// (two in a row, so a single warm-up nudge does not count); a moved
        /// target by one reading against the display width; a retreat by a
        /// run of readings. Only then does the attempt budget decide.
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
                case .ownerUnresponsive:
                    return .stop(.ownerUnresponsive)
                case .superseded:
                    return .stop(.superseded)
                case .overran:
                    return .stop(.overran)
                case .ownerSilent:
                    // An owner with a standing record of ignoring synthetic
                    // events gets no further attempts once it fails this way
                    // again. Deliberately narrower than capping the budget up
                    // front: the loop also retries when the owner *did*
                    // respond but the item did not land, which is a different
                    // failure and still deserves its full budget.
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
        /// On the first attempt it always can. On retries, the only case where
        /// the match can be a coincidence is when the item being moved is
        /// itself a zero-width control item whose bounds may have drifted onto
        /// the target externally; those are gated on observed displacement.
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
        /// Every attempt is bounded by the press-release guard, but eight
        /// bounded attempts still add up; the move as a whole yields the bar
        /// before the cursor watchdog and the callers waiting on the move
        /// gate give up on it.
        static func mayStartAnotherAttempt(elapsed: Duration, deadline: Duration) -> Bool {
            elapsed < deadline
        }

        /// The reason `move` reports when it stops for `failure` on an attempt
        /// it never got to observe (before posting), keeping the mapping in
        /// one place with ``decide(after:state:configuration:)``.
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
            case .cannotComplete, .invalidEventSource, .missingMouseLocation, .eventCreationFailure,
                 .itemNotMovable, .menuTrackingActive, .eventWindowMismatch, .staleDestination,
                 .dropReverted, .moveEngineBusy:
                .other
            }
        }
    }

    // MARK: - Failure attribution

    /// How the failure ledger should file a move error against the item.
    ///
    /// The ledger's unresponsive-owner mark exists for an *app* that ignores
    /// synthetic events — Little Snitch with GUI Scripting disabled is the
    /// recurring case. It is earned by timeouts, and on macOS 26 every hosted
    /// status item's events go to Control Center, not to the app: a timeout
    /// there says Control Center did not relocate the window in time, which
    /// happened for minutes at a stretch while an item's drops were being
    /// reverted by macOS itself, and the field log shows an owner that
    /// answered every press being marked as unresponsive for fourteen days
    /// on the strength of two such timeouts. The mark is therefore filed
    /// only when the owner the events reach is the item's own app.
    ///
    /// A provisional identity is never marked either: its key changes as
    /// soon as the source process resolves, so the mark could not clear.
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
             .staleDestination, .moveSuperseded, .dropReverted,
             .moveEngineBusy, .moveTimedOut:
            return .other
        }
    }

    // MARK: - Refused moves

    /// How long macOS's refusal of a move keeps the item's saved slot from
    /// being overwritten by wherever the refusal left it.
    ///
    /// The refusing state observed in the field lasted about four minutes
    /// and about one minute, and cleared by itself; a landing clears the
    /// record sooner.
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
        case .superseded:
            EventError.moveSuperseded(item)
        case .overran:
            EventError.moveTimedOut(item)
        case .ownerAlwaysSilent, .ownerSilent, .other:
            (lastError as? EventError) ?? EventError.cannotComplete
        case .budgetExhausted:
            EventError.cannotComplete
        }
    }
}
