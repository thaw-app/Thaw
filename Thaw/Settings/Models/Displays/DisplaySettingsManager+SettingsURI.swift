//
//  DisplaySettingsManager+SettingsURI.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel

extension DisplaySettingsManager {
    /// One display configuration change from a thaw:// link.
    typealias ConfigurationUpdate = (DisplayThawBarConfiguration) -> DisplayThawBarConfiguration

    /// Handles per-display settings changed externally via Settings URI scheme.
    func handleExternalPerDisplaySettingsChange(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo, let key = userInfo["key"] as? String, let scope = userInfo["scope"] as? String, let update = Self.update(forKey: key, userInfo: userInfo), let uuids = displayUUIDs(forScope: scope)
        else {
            return
        }
        diagLog.debug("DisplaySettingsManager: thaw:// change for \(key) on \(scope), \(uuids.count) display(s)")
        for uuid in uuids {
            updateConfiguration(forDisplayUUID: uuid, transform: update)
        }
    }

    /// The displays a scope names: one display by UUID, the active one, or the
    /// connected ones with or without the Thaw Bar. Nil for an unknown display.
    func displayUUIDs(forScope scope: String) -> [String]? {
        let connected = NSScreen.managedScreens.compactMap { Bridging.getDisplayUUIDString(for: $0.displayID) }
        if scope.hasPrefix("specific:") {
            let uuid = String(scope.dropFirst("specific:".count))
            guard connected.contains(uuid) || configurations[uuid] != nil else {
                diagLog.warning("DisplaySettingsManager: Ignoring change for unknown display UUID '\(uuid)'")
                return nil
            }
            return [uuid]
        }
        switch scope {
        case "allEnabled":
            return connected.filter { configuration(forUUID: $0).useThawBar }
        // "allNonIceBar" is the Ice-era spelling, kept for script compatibility.
        case "allNonThawBar", "allNonIceBar":
            return connected.filter { !configuration(forUUID: $0).useThawBar }
        case "active":
            guard let uuid = Bridging.getActiveMenuBarDisplayUUID() else {
                diagLog.warning("DisplaySettingsManager: No active menu bar display")
                return nil
            }
            return [uuid]
        default:
            diagLog.warning("DisplaySettingsManager: Ignoring unknown scope '\(scope)'")
            return nil
        }
    }

    /// What a thaw:// key and its value do to one display's configuration, or nil for a bad value.
    static func update(forKey key: String, userInfo: [AnyHashable: Any]) -> ConfigurationUpdate? {
        let toggles = userInfo["toggle"] as? Bool == true
        let flag = userInfo["value"] as? Bool
        let text = userInfo["stringValue"] as? String
        if let (keyPath, apply) = flagKeys[key] {
            return flagUpdate(toggles, flag, keyPath, apply)
        }
        guard let text, let parse = valueKeys[key] else { return nil }
        return parse(text)
    }

    /// The keys with a value, each parsing its text into a change, or nil for a bad value.
    private static let valueKeys: [String: (String) -> ConfigurationUpdate?] = [
        "thawBarLocation": { text in
            Int(text).flatMap(ThawBarLocation.init(rawValue:)).map { location in { $0.withThawBarLocation(location) } }
        },
        "thawBarLayout": { text in
            ThawBarLayout.fromString(text).map { layout in { $0.withThawBarLayout(layout) } }
        },
        "gridColumns": { text in
            Int(text).map { columns in { $0.withGridColumns(Swift.max(2, Swift.min(columns, 10))) } }
        },
        "thawBarItemScale": { text in
            Double(text).map { scale in { $0.withThawBarItemScale(ThawBarItemSize.clampedScale(scale)) } }
        },
        "itemSpacingOffset": { text in
            Double(text).map { offset in { $0.withItemSpacingOffset(Swift.max(-16, Swift.min(offset.rounded(), 16))) } }
        },
    ]

    /// The Boolean keys: the value each reads and how each writes it.
    private static let flagKeys: [String: (KeyPath<DisplayThawBarConfiguration, Bool>, (DisplayThawBarConfiguration, Bool) -> DisplayThawBarConfiguration)] = [
        "useThawBar": (\.useThawBar, { $0.withUseThawBar($1) }),
        "alwaysShowHiddenItems": (\.alwaysShowHiddenItems, { $0.withAlwaysShowHiddenItems($1) }),
        "useThawBarForAlwaysHidden": (\.useThawBarForAlwaysHidden, { $0.withUseThawBarForAlwaysHidden($1) }),
    ]

    /// A Boolean key's change: a toggle flips the current value, a set writes it.
    private static func flagUpdate(
        _ toggles: Bool,
        _ value: Bool?,
        _ keyPath: KeyPath<DisplayThawBarConfiguration, Bool>,
        _ apply: @escaping (DisplayThawBarConfiguration, Bool) -> DisplayThawBarConfiguration
    ) -> ConfigurationUpdate? {
        if toggles {
            return { apply($0, !$0[keyPath: keyPath]) }
        }
        guard let value else { return nil }
        return { apply($0, value) }
    }
}
