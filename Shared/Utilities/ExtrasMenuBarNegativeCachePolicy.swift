//
//  ExtrasMenuBarNegativeCachePolicy.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// TTL ladder for the per-application extras-menu-bar negative cache.
///
/// Only ~16 of ~170 running apps have an extras menu bar, and each AX read
/// blocks the target app's main thread, so a wide scan stutters the system.
/// A "no result" flag cleared on every cleanup was useless, since cleanup runs
/// on any process launch or exit (~9s). Backoff deadlines replace it: early
/// rungs catch late status items, later ones stop re-probing empty apps.
nonisolated enum ExtrasMenuBarNegativeCachePolicy {
    /// How long an application that reported no extras menu bar is skipped,
    /// after `misses` consecutive checks have come back empty (1 = the first
    /// miss).
    ///
    /// Values at or below 1 clamp to the first rung, so errors mean more scanning.
    static func ttl(afterConsecutiveMisses misses: Int) -> Duration {
        switch misses {
        case ...1: .seconds(5)
        case 2: .seconds(30)
        case 3: .seconds(120)
        default: .seconds(300)
        }
    }
}
