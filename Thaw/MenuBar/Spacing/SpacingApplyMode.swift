//
//  SpacingApplyMode.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// When a spacing change becomes visible, and what Thaw is allowed to do
/// to make that happen.
///
/// macOS only reads `NSStatusItemSpacing` when the process owning a status
/// item starts, so a spacing change is invisible to running apps until
/// they restart. `relaunchApps` applies the change right away by
/// restarting the apps Thaw can safely bring back (see
/// ``SpacingRelaunchPolicy``). `writeOnly` writes the preference and
/// leaves every app running; the new spacing appears the next time each
/// owner starts on its own, after the next login, or when the user
/// reopens the app.
///
/// The trade-off the user is choosing: disruption now versus a delay.
/// See `FREQUENT_ISSUES.md` ("What Thaw will and won't quit").
nonisolated enum SpacingApplyMode: String, CaseIterable, Codable {
    /// Write the preference and restart the apps Thaw can bring back so
    /// the new spacing shows up immediately.
    case relaunchApps

    /// Write the preference and leave every app running. The new spacing
    /// takes effect the next time each status-item owner starts on its
    /// own (after a restart, or when the app is reopened).
    case writeOnly
}
