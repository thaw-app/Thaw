//
//  SettingsURIHandler+Appearance.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

extension SettingsURIHandler {
    /// Saves a boolean and announces it. The old blackSettingsBackground key sets the appearance
    /// that replaced it instead, so links written for the old switch keep working.
    static func applyBooleanSetting(_ value: Bool, key: String, entry: SettingURIEntry) -> Bool {
        if entry.defaultsKey == .blackSettingsBackground {
            applySettingsAppearance(SettingsAppearance.stored().applyingLegacyBlackBackground(value))
            return true
        }
        Defaults.set(value, forKey: entry.defaultsKey)
        postSettingsDidChangeNotification(key: key, value: value)
        return true
    }

    /// Handles "thaw://set?key=settingsAppearance&value=system|light|dark|black", or 3, 0, 1 or 2.
    static func handleAppearanceSet(_ value: String) -> Bool {
        guard let appearance = SettingsAppearance.fromString(value) else {
            diagLog.warning("Settings URI: Invalid settingsAppearance value '\(value)'. Valid: system (3), light (0), dark (1), black (2)")
            return false
        }
        applySettingsAppearance(appearance)
        diagLog.info("Settings URI: Set settingsAppearance = \(appearance.uriName) (\(appearance.rawValue))")
        return true
    }

    /// Saves the appearance and announces it under settingsAppearance, whichever key asked.
    private static func applySettingsAppearance(_ appearance: SettingsAppearance) {
        Defaults.set(appearance.rawValue, forKey: .settingsAppearance)
        postSettingsDidChangeNotification(key: "settingsAppearance", rawEnumValue: appearance.rawValue)
    }
}

extension SettingsAppearance {
    /// What thaw://get reports for settingsAppearance.
    var uriValue: [String: Any] {
        [
            "value": uriName,
            "rawValue": rawValue,
            "type": "enum",
            "validValues": ["system": 3, "light": 0, "dark": 1, "black": 2],
        ]
    }
}
