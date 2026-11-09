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

/// How a profile file tells whether it stores the Always Hidden switch.
nonisolated extension Profile {
    private enum LegacyAdvancedKey: String, CodingKey {
        case enableAlwaysHiddenSection
    }

    /// Newer files say so under their own key. In files from before the key, the saved advancedSettings
    /// holding the switch tells, which a rewrite such as a rename would otherwise make true.
    static func readsStoredAlwaysHiddenSwitch(from container: KeyedDecodingContainer<CodingKeys>) throws -> Bool {
        try container.decodeIfPresent(Bool.self, forKey: .storesAlwaysHiddenSection)
            ?? (try? container.nestedContainer(keyedBy: LegacyAdvancedKey.self, forKey: .advancedSettings))?
            .contains(.enableAlwaysHiddenSection) ?? false
    }
}
