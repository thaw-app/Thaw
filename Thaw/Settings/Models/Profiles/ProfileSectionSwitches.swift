//
//  ProfileSectionSwitches.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// A profile sets Always Hidden only when its file stores the switch: older
/// files read it as off, so they may turn it on but never off. The overflow
/// switch stays the user's.
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
