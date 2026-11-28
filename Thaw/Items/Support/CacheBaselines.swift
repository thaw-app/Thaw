//
//  CacheBaselines.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// What the last cache pass read of the bar, which later passes and polls compare the live bar against.
///
/// A pass advances the baselines before it knows whether it publishes. One that publishes nothing puts
/// them back, or the next comparison would find the bar unchanged and skip items that never reached the cache.
nonisolated struct CacheBaselines {
    /// The values one pass reads.
    struct Reading: Equatable {
        /// Window identifiers of the managed items as the previous pass
        /// enumerated them, already flipped out of Window Server order.
        var itemWindowIDs = [CGWindowID]()

        /// Filter these transient clone IDs from change comparisons so clone churn does not trigger recaching.
        var cloneWindowIDs = Set<CGWindowID>()

        /// Ordered owner/title identities for macOS 27, where synthetic AX window IDs churn without movement.
        /// Stable identities prevent a recache loop while detecting real additions, removals, and reorders.
        var itemSignature = [String]()
    }

    private(set) var current = Reading()

    /// The baselines as the running pass found them.
    private var beforePass = Reading()

    /// Keeps the baselines for putBack(). Call before a pass's first advance.
    mutating func beginPass() {
        beforePass = current
    }

    mutating func advance(itemWindowIDs: [CGWindowID], cloneWindowIDs: Set<CGWindowID>) {
        current.itemWindowIDs = itemWindowIDs
        current.cloneWindowIDs = cloneWindowIDs
    }

    mutating func advance(itemSignature: [String]) {
        current.itemSignature = itemSignature
    }

    /// Undoes the advances since beginPass().
    mutating func putBack() {
        current = beforePass
    }
}
