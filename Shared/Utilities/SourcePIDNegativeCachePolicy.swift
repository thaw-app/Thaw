//
//  SourcePIDNegativeCachePolicy.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// TTL ladder for the source-PID negative cache.
///
/// The first full AX scan after launch routinely under-resolves: other apps'
/// accessibility trees are still warming up, so a scan that runs seconds
/// after launch can miss windows that a scan half a minute later resolves.
/// The app's resolution requests are also front-loaded into its startup
/// settling window. A flat TTL as long as that window absorbs every retry —
/// each window fails one cold scan, is barred from initiating another until
/// after the app has stopped asking, and the cache never converges.
///
/// Short deadlines for the first failures let the settling window retry a
/// window while a better scan result is still likely; repeated failures back
/// off to the steady-state TTL that guards against the scan storms the
/// negative cache exists to prevent.
nonisolated enum SourcePIDNegativeCachePolicy {
    /// The negative-cache deadline applied after `failures` consecutive
    /// full scans have left a window unresolved (1 = the first failure).
    ///
    /// Values at or below 1 clamp to the first rung so a bookkeeping error
    /// upstream degrades to more scanning, never to a permanent bar.
    static func ttl(afterConsecutiveFailures failures: Int) -> Duration {
        switch failures {
        case ...1: .seconds(5)
        case 2: .seconds(15)
        default: .seconds(60)
        }
    }
}
