//
//  MoveCircuitBreaker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Trips when reordering activity runs away, and pauses it.
///
/// Two failure modes it stops. Icon dancing: a convergence pass disagrees with
/// the bar, writes, the bar flaps, the next pass writes again, and dozens of
/// moves land in a few seconds with the icons visibly shuffling. Cursor
/// kidnapping: repeated synthetic drags hold the pointer, so the mouse stops
/// responding. A handful of drags in a row is already too many.
///
/// Both are counted in a sliding window. Past a limit the breaker opens and
/// every reorder path refuses for a cooldown, which lengthens with each
/// successive trip so a bar that flaps cannot retry forever. Reordering resumes
/// on its own after the cooldown, so an explicit user move is never lost, and a
/// quiet period resets the backoff.
@MainActor
final class MoveCircuitBreaker {
    /// A counted reorder activity.
    enum Signal {
        /// Any write to the position table: a single move, a section apply, a
        /// structural respace. The "dancing" signal.
        case storeWrite
        /// A synthetic Command-drag, which holds the cursor. The "kidnap" signal.
        case syntheticDrag
        /// A write the bar did not honour.
        case failedVerification
    }

    /// How far back the counts look.
    static nonisolated let window: Duration = .seconds(10)
    /// Store writes allowed in the window before tripping.
    static nonisolated let storeWriteLimit = 30
    /// Synthetic drags allowed in the window before tripping. Deliberately low:
    /// each one takes the pointer.
    static nonisolated let dragLimit = 6
    /// Failed verifications allowed in the window before tripping.
    static nonisolated let failureLimit = 8
    /// First cooldown after a trip.
    static nonisolated let initialCooldown: Duration = .seconds(60)
    /// Ceiling on the exponential backoff.
    static nonisolated let maximumCooldown: Duration = .seconds(600)
    /// How long without a trip before the backoff resets to the initial value.
    static nonisolated let backoffResetInterval: Duration = .seconds(300)

    private struct Event {
        let at: ContinuousClock.Instant
        let signal: Signal
    }

    private var events: [Event] = []
    private var openUntil: ContinuousClock.Instant?
    private var lastTripAt: ContinuousClock.Instant?
    private var cooldown: Duration = MoveCircuitBreaker.initialCooldown
    private var trips = 0

    /// Whether reordering is paused right now.
    var isOpen: Bool {
        guard let openUntil else { return false }
        return ContinuousClock.now < openUntil
    }

    /// Diagnostics for the log and the audit.
    var stateDescription: String {
        let now = ContinuousClock.now
        let openFor = openUntil.map { max(Duration.zero, now.duration(to: $0)) } ?? .zero
        return "trips=\(trips) open=\(isOpen) openFor=\(openFor) window=\(events.count) cooldown=\(cooldown)"
    }

    /// Records activity and trips when a limit is crossed. Returns whether the
    /// breaker is open afterwards.
    @discardableResult
    func note(_ signal: Signal) -> Bool {
        let now = ContinuousClock.now
        prune(before: now)
        events.append(Event(at: now, signal: signal))
        if isOpen {
            return true
        }

        let storeWrites = events.count { $0.signal == .storeWrite }
        let drags = events.count { $0.signal == .syntheticDrag }
        let failures = events.count { $0.signal == .failedVerification }

        var reasons = [String]()
        if storeWrites > Self.storeWriteLimit {
            reasons.append("\(storeWrites) store writes")
        }
        if drags > Self.dragLimit {
            reasons.append("\(drags) synthetic drags")
        }
        if failures > Self.failureLimit {
            reasons.append("\(failures) failed verifications")
        }
        guard !reasons.isEmpty else { return false }

        openFor(reason: reasons.joined(separator: ", "), now: now)
        return true
    }

    /// Opens the breaker for the current cooldown and doubles it for next time.
    private func openFor(reason: String, now: ContinuousClock.Instant) {
        // A trip long enough after the last one means the bar had settled, so
        // the backoff starts over rather than punishing a one-off.
        if let lastTripAt, lastTripAt.duration(to: now) > Self.backoffResetInterval {
            cooldown = Self.initialCooldown
        }
        lastTripAt = now
        trips += 1
        openUntil = now.advanced(by: cooldown)
        MenuBarItemManager.diagLog.error(
            "Move circuit breaker tripped: \(reason) within \(Self.window); "
                + "pausing reordering for \(cooldown) (\(stateDescription))"
        )
        cooldown = min(cooldown * 2, Self.maximumCooldown)
    }

    /// The user retried a move by hand.
    ///
    /// An explicit move is one deliberate action, not a storm, so it is allowed
    /// through even while the breaker is open. On success the caller clears the
    /// breaker so automatic passes can resume; the escalated cooldown is kept,
    /// so if the storm returns it backs off for longer than last time.
    func noteUserOverride() {
        events.removeAll()
        openUntil = nil
        MenuBarItemManager.diagLog.info(
            "Move circuit breaker cleared by a user move (\(stateDescription))"
        )
    }

    private func prune(before now: ContinuousClock.Instant) {
        events.removeAll { now - $0.at > Self.window }
    }
}
