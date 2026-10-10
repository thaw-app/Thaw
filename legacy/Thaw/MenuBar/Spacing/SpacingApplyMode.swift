//
//  SpacingApplyMode.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// How a spacing change is applied.
///
/// macOS reads `NSStatusItemSpacing` only when a status item's owner starts,
/// so running apps don't see a change until they restart. See
/// `FREQUENT_ISSUES.md` ("What Thaw will and won't quit").
nonisolated enum SpacingApplyMode: String, CaseIterable, Codable {
    /// Write the preference and restart the apps Thaw can safely bring back
    /// (see ``SpacingRelaunchPolicy``).
    case relaunchApps

    /// Write the preference and leave every app running. Each owner picks up
    /// the new spacing the next time it starts.
    case writeOnly
}
