//
//  TimestampWindow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import DequeModule

/// The times of recent events in a sliding window, for rate limits.
///
/// Times must be recorded in order: expired ones are dropped from the front.
nonisolated struct TimestampWindow {
    /// When an event drops out of the window.
    enum Expiry {
        /// Once it is as old as the window.
        case atLength
        /// Once it is older than the window.
        case pastLength
    }

    let length: Duration
    let expiry: Expiry
    private var stamps = Deque<ContinuousClock.Instant>()

    init(length: Duration, expiry: Expiry) {
        self.length = length
        self.expiry = expiry
    }

    var count: Int {
        stamps.count
    }

    mutating func removeExpired(at now: ContinuousClock.Instant) {
        while let oldest = stamps.first, isExpired(oldest, at: now) {
            stamps.removeFirst()
        }
    }

    /// Drops what has expired by now, then records an event at now.
    mutating func record(at now: ContinuousClock.Instant) {
        removeExpired(at: now)
        stamps.append(now)
    }

    mutating func removeAll() {
        stamps.removeAll()
    }

    private func isExpired(_ stamp: ContinuousClock.Instant, at now: ContinuousClock.Instant) -> Bool {
        let age = stamp.duration(to: now)
        return switch expiry {
        case .atLength: age >= length
        case .pastLength: age > length
        }
    }
}
