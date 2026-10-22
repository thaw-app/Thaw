//
//  OnScreenItemSnapshot.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Holds the most recent on-screen menu bar items recorded by a cache pass,
/// together with when they were seen.
///
/// Consumers that need "the items as of the last settled enumeration" hold
/// this snapshot directly rather than reaching through the manager whose cache
/// pass produces it. Lives in MenuBarModel because both sides of the
/// engine/frontend split need it.
@MainActor
public final class OnScreenItemSnapshot {
    public private(set) var items: [MenuBarItem] = []
    public private(set) var timestamp: ContinuousClock.Instant?

    /// Numbers the walk behind items when that walk read every owner, and is
    /// nil when it did not or before any walk has. Each complete walk gets a
    /// larger number than the one before, and the number stays the same until
    /// the next update.
    public private(set) var completedWalkGeneration: Int?
    private var completedWalkCount = 0

    public init() {}

    /// Records a fresh enumeration of the on-screen bar. Pass true for
    /// fromCompleteWalk only when the walk read every running owner, without
    /// running out of time or being skipped.
    public func update(_ items: [MenuBarItem], fromCompleteWalk: Bool = false) {
        self.items = items
        timestamp = .now
        if fromCompleteWalk {
            completedWalkCount += 1
            completedWalkGeneration = completedWalkCount
        } else {
            completedWalkGeneration = nil
        }
    }
}
