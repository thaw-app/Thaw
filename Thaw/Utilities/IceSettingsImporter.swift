//
//  IceSettingsImporter.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation

/// A type that handles importing settings from Ice.
@MainActor
struct IceSettingsImporter {
    private let diagLog = DiagLog(category: "IceSettingsImporter")

    /// The bundle identifier for Ice.
    private static let iceBundleIdentifier = "com.jordanbaird.Ice"

    /// Checks if Ice settings are available for import.
    func hasIceSettings() -> Bool {
        guard
            let iceUserDefaults = UserDefaults(suiteName: Self.iceBundleIdentifier),
            let domain = iceUserDefaults.persistentDomain(forName: Self.iceBundleIdentifier)
        else {
            return false
        }

        return !domain.isEmpty
    }

    /// Imports settings from Ice if available.
    /// - Returns: A tuple indicating success and the number of settings imported.
    func importIceSettings() -> (success: Bool, settingsImported: Int) {
        guard let iceUserDefaults = UserDefaults(suiteName: Self.iceBundleIdentifier) else {
            diagLog.warning("Could not access Ice user defaults")
            return (false, 0)
        }

        let iceSettings = iceUserDefaults.dictionaryRepresentation()
        var settingsImported = 0

        diagLog.info("Starting import of Ice settings. Found \(iceSettings.count) potential settings")

        // Import General Settings
        settingsImported += importGeneralSettings(from: iceSettings)

        // Import Advanced Settings
        settingsImported += importAdvancedSettings(from: iceSettings)

        // Import Hotkeys Settings
        settingsImported += importHotkeysSettings(from: iceSettings)

        // Import Appearance Settings
        settingsImported += importAppearanceSettings(from: iceSettings)

        diagLog.info("Successfully imported \(settingsImported) settings from Ice")
        return (true, settingsImported)
    }

    /// Imports general settings from Ice.
    private func importGeneralSettings(from iceSettings: [String: Any]) -> Int {
        var imported = 0

        let mappings: [(Defaults.Key, String)] = [
            (.showIceIcon, "ShowIceIcon"),
            (.iceIcon, "IceIcon"),
            (.customIceIconIsTemplate, "CustomIceIconIsTemplate"),
            // Legacy Thaw Bar keys kept for migration compatibility
            (.useIceBar, "UseIceBar"),
            (.iceBarLocation, "IceBarLocation"),
            (.showOnClick, "ShowOnClick"),
            (.showOnHover, "ShowOnHover"),
            (.showOnScroll, "ShowOnScroll"),
            (.autoRehide, "AutoRehide"),
            (.rehideStrategy, "RehideStrategy"),
            (.rehideInterval, "RehideInterval"),
        ]

        for (key, iceKey) in mappings {
            if let value = iceSettings[iceKey] {
                Defaults.set(value, forKey: key)
                imported += 1
                diagLog.debug("Imported general setting: \(iceKey)")
            }
        }

        // Generate per-display configurations when importing Thaw Bar settings
        imported += importPerDisplayIceBarSettings(from: iceSettings)

        return imported
    }

    /// Generates per-display Thaw Bar configurations from imported Ice settings.
    private func importPerDisplayIceBarSettings(from iceSettings: [String: Any]) -> Int {
        guard let useIceBar = iceSettings["UseIceBar"] as? Bool, useIceBar else {
            return 0
        }

        let locationRaw = iceSettings["IceBarLocation"] as? Int ?? 0
        let location = IceBarLocation(rawValue: locationRaw) ?? .dynamic
        let onlyOnNotched = iceSettings["UseIceBarOnlyOnNotchedDisplay"] as? Bool ?? false

        let configs = DisplayIceBarConfiguration.buildConfigurations(
            onlyOnNotched: onlyOnNotched,
            location: location
        )

        guard !configs.isEmpty else { return 0 }

        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(configs)
            Defaults.set(data, forKey: .displayIceBarConfigurations)
            Defaults.set(true, forKey: .hasMigratedPerDisplayIceBar)
            diagLog.info("Generated per-display Thaw Bar configs for \(configs.count) display(s) from Ice import")
            return 1
        } catch {
            diagLog.error("Failed to encode per-display Thaw Bar configs during import: \(error)")
            return 0
        }
    }

    /// Imports advanced settings from Ice.
    private func importAdvancedSettings(from iceSettings: [String: Any]) -> Int {
        var imported = 0

        let mappings: [(Defaults.Key, String)] = [
            (.enableAlwaysHiddenSection, "EnableAlwaysHiddenSection"),
            (.showAllSectionsOnUserDrag, "ShowAllSectionsOnUserDrag"),
            (.sectionDividerStyle, "SectionDividerStyle"),
            (.hideApplicationMenus, "HideApplicationMenus"),
            (.enableSecondaryContextMenu, "EnableSecondaryContextMenu"),
            (.showOnHoverDelay, "ShowOnHoverDelay"),
        ]

        for (key, iceKey) in mappings {
            if let value = iceSettings[iceKey] {
                Defaults.set(value, forKey: key)
                imported += 1
                diagLog.debug("Imported advanced setting: \(iceKey)")
            }
        }

        return imported
    }

    /// Imports hotkeys settings from Ice.
    private func importHotkeysSettings(from iceSettings: [String: Any]) -> Int {
        // Ice stores hotkeys as a dictionary of action identifiers to encoded `KeyCombination` data.
        if let hotkeysDict = iceSettings["Hotkeys"] as? [String: Any] {
            let dataDict = hotkeysDict.compactMapValues { $0 as? Data }
            guard !dataDict.isEmpty else {
                return 0
            }
            Defaults.set(dataDict, forKey: .hotkeys)
            diagLog.debug("Imported \(dataDict.count) hotkey settings")
            return dataDict.count
        }

        // Fallback in case the value is already a data blob.
        if let hotkeysData = iceSettings["Hotkeys"] as? Data {
            Defaults.set(hotkeysData, forKey: .hotkeys)
            diagLog.debug("Imported hotkeys settings")
            return 1
        }

        return 0
    }

    /// Imports appearance settings from Ice.
    private func importAppearanceSettings(from iceSettings: [String: Any]) -> Int {
        var imported = 0

        // Import V2 appearance configuration if available
        if let appearanceData = iceSettings["MenuBarAppearanceConfigurationV2"] as? Data {
            Defaults.set(appearanceData, forKey: .menuBarAppearanceConfigurationV2)
            imported += 1
            diagLog.debug("Imported appearance configuration V2")
        }
        // Fallback to V1 if V2 not available
        else if let appearanceData = iceSettings["MenuBarAppearanceConfiguration"] as? Data {
            // This will be handled by the existing migration system
            Defaults.set(appearanceData, forKey: .menuBarAppearanceConfiguration)
            imported += 1
            diagLog.debug("Imported appearance configuration V1")
        }

        return imported
    }

    /// Imports control item positions and visibility flags from Ice.
    ///
    /// NOTE: We no longer migrate control item autosave data to avoid
    /// collapsing sections when macOS repositions status items. Users
    /// will need to re-place section dividers manually after import.
    private func importControlItemSettings(from _: UserDefaults) -> Int {
        return 0
    }
}
