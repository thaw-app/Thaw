//
//  SourcePIDNegativeCachePolicy.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// TTL ladder for the source-PID negative cache.
///
/// The first AX scan after launch under-resolves while other apps' trees warm
/// up, and the app's requests are front-loaded into its startup window. A flat
/// TTL outlasts every retry and the cache never converges, so early failures
/// get short deadlines and repeats back off to the steady-state TTL.
nonisolated enum SourcePIDNegativeCachePolicy {
    /// The negative-cache deadline applied after `failures` consecutive
    /// full scans have left a window unresolved (1 = the first failure).
    ///
    /// Values at or below 1 clamp to the first rung, so errors mean more scanning.
    static func ttl(afterConsecutiveFailures failures: Int) -> Duration {
        switch failures {
        case ...1: .seconds(5)
        case 2: .seconds(15)
        default: .seconds(60)
        }
    }
}
