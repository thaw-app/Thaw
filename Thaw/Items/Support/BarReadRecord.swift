//
//  BarReadRecord.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// The last read of the bar the item cache took, numbered so a caller that coalesced into a
/// running read can tell it saw no new read, and marked when the read missed part of the bar.
nonisolated struct BarReadRecord: Equatable, Sendable {
    /// What one cache pass learned about its read, noted when the pass ends.
    struct Read: Equatable, Sendable {
        /// Whether every owner known to have items answered this read; a quick read can skip apps without items.
        var hasFreshKnownInventory: Bool
        /// The same, except for apps that aren't answering and whose items Thaw already holds.
        var hasSteadyKnownInventory: Bool
        /// Whether the pass filled the read's gaps from older cached items.
        var mergedWithOlderItems = false

        /// A fresh read is steady too, so steady only needs saying when it differs.
        init(hasFreshKnownInventory: Bool, hasSteadyKnownInventory: Bool? = nil, mergedWithOlderItems: Bool = false) {
            self.hasFreshKnownInventory = hasFreshKnownInventory
            self.hasSteadyKnownInventory = hasSteadyKnownInventory ?? hasFreshKnownInventory
            self.mergedWithOlderItems = mergedWithOlderItems
        }
    }

    /// Goes up by one with every read, so the same number means the same read.
    private(set) var generation: UInt64 = 0
    /// False until a first read, and after a read with stale owners or a merge with older items.
    private(set) var isComplete = false
    /// Complete, or missing only apps that aren't answering and whose items are already known.
    /// Enough for the settle; a write still needs isComplete, because that app's positions are old.
    private(set) var isSteady = false

    /// Nil, from a pass that ended before it read the bar, leaves the record as it was.
    mutating func note(_ read: Read?) {
        guard let read else { return }
        generation &+= 1
        isComplete = read.hasFreshKnownInventory && !read.mergedWithOlderItems
        isSteady = read.hasSteadyKnownInventory && !read.mergedWithOlderItems
    }
}
