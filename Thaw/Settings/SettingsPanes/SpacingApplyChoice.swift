//
//  SpacingApplyChoice.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// The one choice the Displays pane offers for a spacing change. It is stored as the apply
/// mode and the confirmation switch, which other code reads, so both keep their meaning.
nonisolated enum SpacingApplyChoice: Hashable, CaseIterable {
    case askFirst
    case relaunchNow
    case waitForRestart

    init(mode: SpacingApplyMode, confirms: Bool) {
        switch mode {
        case .writeOnly: self = .waitForRestart
        case .relaunchApps: self = confirms ? .askFirst : .relaunchNow
        }
    }

    var mode: SpacingApplyMode {
        self == .waitForRestart ? .writeOnly : .relaunchApps
    }

    /// Nil when the choice doesn't relaunch, which leaves the stored switch as it was.
    var confirms: Bool? {
        switch self {
        case .askFirst: true
        case .relaunchNow: false
        case .waitForRestart: nil
        }
    }

    /// Whether Apply to All Displays asks first. Waiting for restarts with a profile active
    /// saves where Save spacing to every profile says; with no profile it still asks.
    static func globalApplyAsks(mode: SpacingApplyMode, confirms: Bool, hasActiveProfile: Bool) -> Bool {
        guard confirms else { return false }
        return mode == .relaunchApps || !hasActiveProfile
    }
}
