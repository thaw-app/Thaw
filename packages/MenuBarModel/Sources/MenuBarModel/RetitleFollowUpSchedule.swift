//
//  RetitleFollowUpSchedule.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

/// Decides when the bar is read once more to catch an app renaming its item, since a new title alone starts no read.
/// It asks for one after a little over a minute without a read, and only a few times per app.
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

    public init() {}

    /// Notes a fresh read and cancels the follow-up it replaces, so one runs only after the whole delay without a read.
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
