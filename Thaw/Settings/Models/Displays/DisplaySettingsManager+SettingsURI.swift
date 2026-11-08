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
            let userInfo = notification.userInfo,
            let key = userInfo["key"] as? String,
            let scope = userInfo["scope"] as? String,
            let update = Self.update(forKey: key, userInfo: userInfo),
            let uuids = displayUUIDs(forScope: scope)
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
        default:
            guard let uuid = Bridging.getActiveMenuBarDisplayUUID() else {
                diagLog.warning("DisplaySettingsManager: No active menu bar display for \(scope)")
                return nil
            }
            return [uuid]
        }
    }

    /// What a thaw:// key and its value do to one display's configuration, or nil for a bad value.
    static func update(forKey key: String, userInfo: [AnyHashable: Any]) -> ConfigurationUpdate? {
        let toggles = userInfo["toggle"] as? Bool == true
        let flag = userInfo["value"] as? Bool
        let text = userInfo["stringValue"] as? String
        switch key {
        case "useThawBar":
            return flagUpdate(toggles, flag, \.useThawBar) { $0.withUseThawBar($1) }
        case "alwaysShowHiddenItems":
            return flagUpdate(toggles, flag, \.alwaysShowHiddenItems) { $0.withAlwaysShowHiddenItems($1) }
        case "useThawBarForAlwaysHidden":
            return flagUpdate(toggles, flag, \.useThawBarForAlwaysHidden) { $0.withUseThawBarForAlwaysHidden($1) }
        case "thawBarLocation":
            guard let location = text.flatMap(Int.init).flatMap(ThawBarLocation.init(rawValue:)) else { return nil }
            return { $0.withThawBarLocation(location) }
        case "thawBarLayout":
            guard let layout = text.flatMap(ThawBarLayout.fromString) else { return nil }
            return { $0.withThawBarLayout(layout) }
        case "gridColumns":
            guard let columns = text.flatMap(Int.init) else { return nil }
            return { $0.withGridColumns(Swift.max(2, Swift.min(columns, 10))) }
        case "thawBarItemScale":
            guard let scale = text.flatMap(Double.init) else { return nil }
            return { $0.withThawBarItemScale(ThawBarItemSize.clampedScale(scale)) }
        case "itemSpacingOffset":
            guard let offset = text.flatMap(Double.init) else { return nil }
            return { $0.withItemSpacingOffset(Swift.max(-16, Swift.min(offset.rounded(), 16))) }
        default:
            return nil
        }
    }

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
