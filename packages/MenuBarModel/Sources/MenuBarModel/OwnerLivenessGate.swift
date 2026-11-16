//
//  OwnerLivenessGate.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Decides when the periodic liveness check has to read the whole process table, which asks the system about every running app.
/// It reads only when a cached owner's process is gone, the list of running apps changed, or the last read is older than the backstop.
public struct OwnerLivenessGate<Signature: Equatable & Sendable>: Sendable {
    /// How long a read is trusted while nothing cheaper has changed. Covers an
    /// app the system still lists after it has quit.
    public static var backstop: Duration { .seconds(30) }

    private var lastRead: (signature: Signature, at: ContinuousClock.Instant)?

    public init() {}

    /// Whether the process table has to be read now: an owner's process is gone, the list of running apps changed, or the backstop passed.
    public func isReadDue(ownersAlive: Bool, signature: Signature, now: ContinuousClock.Instant) -> Bool {
        guard let lastRead, ownersAlive, lastRead.signature == signature else { return true }
        return lastRead.at.duration(to: now) >= Self.backstop
    }

    /// Records a read of the process table taken while the list had this signature.
    public mutating func noteRead(signature: Signature, at instant: ContinuousClock.Instant) {
        lastRead = (signature, instant)
    }
}
