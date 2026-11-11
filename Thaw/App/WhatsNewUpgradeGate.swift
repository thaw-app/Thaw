//
//  WhatsNewUpgradeGate.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Decides whether a launch opens What's New by itself.
@MainActor
enum WhatsNewUpgradeGate {
    /// Records current as the last version seen and reports whether this launch is an update that should open What's New.
    ///
    /// The version is recorded even when opensAfterUpdate is off, so turning the setting back on later does not replay an old changelog.
    static func recordVersion(_ current: String, opensAfterUpdate: Bool) -> Bool {
        let lastSeen = Defaults.string(forKey: .lastWhatsNewVersion)
        guard lastSeen != current else { return false }
        Defaults.set(current, forKey: .lastWhatsNewVersion)
        // A first launch has no last version; onboarding greets new users instead.
        return lastSeen != nil && opensAfterUpdate
    }
}
