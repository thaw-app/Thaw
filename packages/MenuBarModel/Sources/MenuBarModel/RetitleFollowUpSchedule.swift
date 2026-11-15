//
//  RetitleFollowUpSchedule.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

/// Decides when the bar is read once more to catch an app renaming its item.
///
/// Thaw reads the bar when something on it changes, and a new title alone is not such a change. On a
/// quiet bar FreshVolatileTitleLearner could wait a long time for the second read it needs. After a
/// read that leaves an app worth comparing, this asks for another read once the bar has gone a little
/// over a minute without one. Each app can cause only a few of these, so an app whose title never
/// changes stops causing reads.
public struct RetitleFollowUpSchedule: Sendable {
    /// Just over a minute, so a clock's change of minute always falls between two reads.
    public static let delay = Duration.seconds(65)

    /// Follow-up reads one app can cause while Thaw runs. The second is for a first comparison spoiled
    /// by the item moving, or by a new title that changed its width.
    public static let followUpsPerOwner = 2

    /// Follow-ups left for each app that has used one.
    private var followUpsLeft = [String: Int]()
    /// The apps the claimed follow-up is for.
    private var awaited = Set<String>()
    private var task: Task<Void, Never>?

    /// A schedule with nothing waiting and every app's follow-ups unused.
    public init() {}

    /// Notes a fresh read and cancels the follow-up it replaces, so one runs only after the bar has gone
    /// the whole delay without a read.
    /// - Parameter candidates: Apps the read left worth comparing with the next one.
    /// - Returns: How long to wait before reading again, or nil when no candidate has a follow-up left.
    public mutating func claim(candidates: Set<String>) -> Duration? {
        task?.cancel()
        task = nil
        awaited = candidates.filter { followUpsLeft[$0, default: Self.followUpsPerOwner] > 0 }
        return awaited.isEmpty ? nil : Self.delay
    }

    /// Holds the task that waits out a claimed follow-up.
    public mutating func arm(_ task: Task<Void, Never>) {
        self.task = task
    }

    /// Notes that the wait is over and the read is about to run, and takes one follow-up from each app
    /// it is for. The read's own claim then leaves the running task alone.
    public mutating func fired() {
        task = nil
        for owner in awaited {
            followUpsLeft[owner, default: Self.followUpsPerOwner] -= 1
        }
        awaited = []
    }
}
