//
//  ExtrasBarAbsenceLedger.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ApplicationServices

/// Apps that answered the walk with no extras menu bar, so later walks can leave them out for a while.
///
/// Most running apps never show a menu bar item, and asking one with no Accessibility server fails a
/// launchd lookup every time. An answer counts only once it repeats after confirmationDelay, so an app
/// still starting up is asked again, and a counted answer expires after its recheck interval.
nonisolated struct ExtrasBarAbsenceLedger: Sendable {
    enum Absence: Equatable, Sendable {
        /// The app answered that it has no extras menu bar.
        case noExtrasBar
        /// The app has no Accessibility server, so the read failed at once.
        case noAXServer

        /// How long walks leave the app out before asking it again.
        /// An app with an Accessibility server can turn on a status item at any time.
        var recheckInterval: Duration {
            switch self {
            case .noExtrasBar: .seconds(120)
            case .noAXServer: .seconds(600)
            }
        }
    }

    /// How long an answer must hold before walks rely on it.
    static let confirmationDelay = Duration.seconds(30)

    /// The longest a failed read may take and still mean the app has no Accessibility server.
    /// A read that timed out fails with the same code, but only after the messaging timeout.
    static let immediateFailureLimit = Duration.milliseconds(50)

    /// What one read of an app's extras bar says about it, or nil when the app might still have one.
    static func absence(for result: AXError, elapsed: Duration) -> Absence? {
        switch result {
        case .noValue, .attributeUnsupported:
            .noExtrasBar
        case .cannotComplete where elapsed < immediateFailureLimit:
            .noAXServer
        default:
            nil
        }
    }

    private struct Record: Sendable {
        /// Guards against a new process that reuses the pid.
        let bundleID: String
        let absence: Absence
        let firstAnsweredAt: ContinuousClock.Instant
        var confirmedAt: ContinuousClock.Instant?
    }

    private var records: [pid_t: Record] = [:]

    /// Records one read of an app's extras bar. Any answer but an absence forgets the app.
    mutating func noteAnswer(_ absence: Absence?, pid: pid_t, bundleID: String, now: ContinuousClock.Instant = .now) {
        guard let absence else {
            records[pid] = nil
            return
        }
        guard var record = records[pid], record.bundleID == bundleID, record.absence == absence else {
            records[pid] = Record(bundleID: bundleID, absence: absence, firstAnsweredAt: now)
            return
        }
        if now - record.firstAnsweredAt >= Self.confirmationDelay {
            record.confirmedAt = now
        }
        records[pid] = record
    }

    /// Whether a walk may leave the app out and keep its last, empty answer.
    func skips(_ pid: pid_t, bundleID: String, now: ContinuousClock.Instant = .now) -> Bool {
        guard let record = records[pid], record.bundleID == bundleID, let confirmedAt = record.confirmedAt else {
            return false
        }
        return now - confirmedAt < record.absence.recheckInterval
    }

    /// Drops apps that have quit.
    mutating func retain(running: Set<pid_t>) {
        records = records.filter { running.contains($0.key) }
    }
}
