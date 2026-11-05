//
//  SettingsURIHandler+ComputedSettings.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

extension SettingsURIHandler {
    /// Booleans that settings compute instead of storing. A get reads them here, never under their
    /// Defaults key, which may still hold a value an older build saved.
    static let computedBooleans: [Defaults.Key: @MainActor () -> Bool] = [
        .enableExperimentalSystemItemHiding: {
            HidingMethod(nativeAppHidingEnabled: Defaults.bool(forKey: .enableNativeAppHiding)).hidesAppleItems
        },
        // The old black background switch, read from the appearance that replaced it.
        .blackSettingsBackground: {
            SettingsAppearance.stored() == .black
        },
    ]
}
