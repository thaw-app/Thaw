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
        writeOnlyConfigurationsReason = Self.linkWriteOnlyReason(confirmRelaunch: confirmSpacingRelaunch)
        defer { writeOnlyConfigurationsReason = nil }
        let previousOffsets = Dictionary(uniqueKeysWithValues: uuids.map { ($0, configuration(forUUID: $0).itemSpacingOffset) })
        for uuid in uuids {
            updateConfiguration(forDisplayUUID: uuid, transform: update)
        }
        if key == "itemSpacingOffset" {
            saveLinkSpacingToProfiles(uuids, previousOffsets: previousOffsets)
        }
    }

    /// Saves a link's spacing to the profiles as the Displays page does, so the next apply keeps it.
    /// A failed save restores the old spacing on the displays it didn't save, so live and saved spacing agree.
    private func saveLinkSpacingToProfiles(_ uuids: [String], previousOffsets: [String: Double]) {
        guard let host = spacingHost else { return }
        var saved = Set<String>()
        do {
            switch unconfirmedSpacingProfileScope {
            case .activeProfile:
                // The active profile takes the whole live configuration at once.
                if let uuid = uuids.first {
                    try host.saveSpacingToProfiles(uuid, configuration(forUUID: uuid).itemSpacingOffset, .activeProfile)
                }
            case .allProfiles:
                for uuid in uuids {
                    try host.saveSpacingToProfiles(uuid, configuration(forUUID: uuid).itemSpacingOffset, .allProfiles)
                    saved.insert(uuid)
                }
            }
        } catch {
            diagLog.error("DisplaySettingsManager: Could not save the link's spacing to profiles: \(error)")
            for (uuid, offset) in previousOffsets where !saved.contains(uuid) {
                updateConfiguration(forDisplayUUID: uuid) { $0.withItemSpacingOffset(offset) }
            }
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

    /// The reason a thaw:// link's change applies its spacing under while a relaunch needs confirming.
    static let settingsLinkReason = "settingsLink"

    /// A link can't show the confirmation the Displays page asks for before it restarts every menu bar app.
    /// While that confirmation is on, a link's spacing is saved and takes effect as each app next starts.
    static func linkWriteOnlyReason(confirmRelaunch: Bool) -> String? {
        confirmRelaunch ? settingsLinkReason : nil
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
            DisplaySettingsManager.finite(text).map { scale in { $0.withThawBarItemScale(ThawBarItemSize.clampedScale(scale)) } }
        },
        "itemSpacingOffset": { text in
            DisplaySettingsManager.finite(text).map { offset in { $0.withItemSpacingOffset(Swift.max(-16, Swift.min(offset.rounded(), 16))) } }
        },
    ]

    /// A number a link may set. "nan" and "inf" parse as numbers, and clamping turns them into a real value.
    static func finite(_ text: String) -> Double? {
        Double(text).flatMap { $0.isFinite ? $0 : nil }
    }

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
