//
//  ProfileSectionSwitches.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// A file that doesn't say it stores the Always Hidden switch only turns it on.
/// The overflow switch stays the user's.
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

/// How a profile file tells whether it stores the Always Hidden switch.
nonisolated extension Profile {
    /// Only a file that says so under its own key. Released builds wrote the switch into every profile
    /// while applying one could only turn it on, so its presence there doesn't mean it was meant to turn it off.
    static func readsStoredAlwaysHiddenSwitch(from container: KeyedDecodingContainer<CodingKeys>) throws -> Bool {
        try container.decodeIfPresent(Bool.self, forKey: .storesAlwaysHiddenSection) ?? false
    }
}
