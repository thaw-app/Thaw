//
//  ExtrasMenuBarNegativeCachePolicy.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// TTL ladder for the per-application extras-menu-bar negative cache.
///
/// A full source-PID scan walks every running application and asks each one
/// for its extras menu bar over the Accessibility API. On a typical system
/// only ~16 of ~170 running applications ever have one, so the other ~155
/// contribute nothing but blocking IPC — and an AX read is serviced by the
/// *target* process, usually on its main thread, so a wide scan makes the
/// whole system stutter rather than just this service.
///
/// A bare "checked, no result" flag is not enough on its own, because the
/// flag has to be cleared periodically: an application can register a status
/// item long after it finishes launching. Clearing it on every cache cleanup
/// made the flag nearly worthless — cleanup is driven by
/// `NSWorkspace.runningApplications`, which churns whenever *any* process on
/// the system starts or exits (observed at ~9s intervals in the field), so
/// every scan re-probed the whole application list.
///
/// Deadlines replace the flag. Repeated misses back off, so an application
/// that has never had an extras menu bar is re-probed at the steady-state
/// interval instead of on every scan, while the early rungs stay short enough
/// to catch an application that publishes a status item shortly after launch.
nonisolated enum ExtrasMenuBarNegativeCachePolicy {
    /// How long an application that reported no extras menu bar is skipped,
    /// after `misses` consecutive checks have come back empty (1 = the first
    /// miss).
    ///
    /// Values at or below 1 clamp to the first rung so a bookkeeping error
    /// upstream degrades to more scanning, never to a permanent bar.
    static func ttl(afterConsecutiveMisses misses: Int) -> Duration {
        switch misses {
        case ...1: .seconds(5)
        case 2: .seconds(30)
        case 3: .seconds(120)
        default: .seconds(300)
        }
    }
}
