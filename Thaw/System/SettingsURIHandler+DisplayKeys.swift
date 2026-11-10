//
//  SettingsURIHandler+DisplayKeys.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

extension SettingsURIHandler {
    /// Per-display settings keys, stored in DisplaySettingsManager rather than Defaults.
    static let perDisplayKeys: [String] = [
        "useThawBar",
        "thawBarLocation",
        "alwaysShowHiddenItems",
        "thawBarLayout",
        "gridColumns",
        "thawBarItemScale",
        "itemSpacingOffset",
        "useThawBarForAlwaysHidden",
    ]

    /// Sets the per-display keys the original handler doesn't know: item size,
    /// item spacing and the Always-Hidden-only choice.
    static func handleDisplayLookSet(key: String, value: String, scope: PerDisplayScope) -> Bool {
        switch key {
        case "thawBarItemScale":
            guard let scale = DisplaySettingsManager.finite(value) else {
                diagLog.warning("Settings URI: Invalid thawBarItemScale value '\(value)'")
                return false
            }
            let clamped = ThawBarItemSize.clampedScale(scale)
            postPerDisplaySettingsDidChangeNotification(key: key, stringValue: String(clamped), scope: scope)
        case "itemSpacingOffset":
            guard let offset = DisplaySettingsManager.finite(value) else {
                diagLog.warning("Settings URI: Invalid itemSpacingOffset value '\(value)'")
                return false
            }
            let clamped = Swift.max(-16, Swift.min(offset.rounded(), 16))
            postPerDisplaySettingsDidChangeNotification(key: key, stringValue: String(clamped), scope: scope)
        case "useThawBarForAlwaysHidden":
            guard let boolValue = parseBool(value) else {
                diagLog.warning("Settings URI: Invalid boolean value '\(value)' for \(key)")
                return false
            }
            postPerDisplaySettingsDidChangeNotification(key: key, value: boolValue, scope: scope)
        default:
            return false
        }
        diagLog.info("Settings URI: Set \(key) = \(value) on \(scope.logDescription)")
        return true
    }

    /// thaw://get for the same keys.
    static func displayLookValue(key: String, config: DisplayThawBarConfiguration) -> [String: Any]? {
        switch key {
        case "thawBarItemScale":
            ["value": config.thawBarItemScale, "type": "double", "range": ["min": ThawBarItemSize.minimumScale, "max": ThawBarItemSize.maximumScale]]
        case "itemSpacingOffset":
            ["value": config.itemSpacingOffset, "type": "double", "range": ["min": -16, "max": 16]]
        case "useThawBarForAlwaysHidden":
            ["value": config.useThawBarForAlwaysHidden, "type": "boolean"]
        default:
            nil
        }
    }
}
