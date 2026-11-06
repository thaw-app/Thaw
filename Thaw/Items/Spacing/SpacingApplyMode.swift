//
//  SpacingApplyMode.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// How a spacing change is applied. macOS reads NSStatusItemSpacing only when
/// a status item's owner starts, so running apps keep theirs until they restart.
nonisolated enum SpacingApplyMode: String, CaseIterable, Codable {
    /// Write the preference and relaunch the apps that own menu bar items.
    case relaunchApps

    /// Write the preference and leave every app running.
    case writeOnly
}
