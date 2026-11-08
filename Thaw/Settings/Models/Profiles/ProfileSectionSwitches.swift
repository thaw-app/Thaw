//
//  ProfileSectionSwitches.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Older files without the Always Hidden switch read it as off, so they only turn it
/// on. The overflow switch stays the user's.
nonisolated extension AdvancedSettingsSnapshot {
    func merged(onto current: AdvancedSettingsSnapshot, storesAlwaysHiddenSection: Bool) -> AdvancedSettingsSnapshot {
        var merged = self
        if !storesAlwaysHiddenSection {
            merged.enableAlwaysHiddenSection = current.enableAlwaysHiddenSection || enableAlwaysHiddenSection
        }
        merged.enableMenuBarItemOverflow = current.enableMenuBarItemOverflow
        return merged
    }
}
