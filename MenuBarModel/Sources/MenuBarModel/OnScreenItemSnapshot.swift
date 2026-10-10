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

    public init() {}

    /// Records a fresh enumeration of the on-screen bar.
    public func update(_ items: [MenuBarItem]) {
        self.items = items
        timestamp = .now
    }
}
