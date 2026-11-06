//
//  ProfileSectionSwitches.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// A profile may turn Always Hidden on, so its items have a section to go to,
/// but never off, and the overflow switch stays the user's.
nonisolated extension AdvancedSettingsSnapshot {
    func merged(onto current: AdvancedSettingsSnapshot) -> AdvancedSettingsSnapshot {
        var merged = self
        merged.enableAlwaysHiddenSection = current.enableAlwaysHiddenSection || enableAlwaysHiddenSection
        merged.enableMenuBarItemOverflow = current.enableMenuBarItemOverflow
        return merged
    }
}
