//
//  SystemMenuBarModuleCatalog.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - SystemMenuBarModule

/// An Apple-owned menu bar module and the names each subsystem addresses it
/// by: Control Center matches a menu-extra title, the runtime kit a tag.title.
public struct SystemMenuBarModule: Equatable, Sendable {
    /// Stable identifier for diagnostics, tests, and the runtime kit's own
    /// lookups; never used as a runtime match key on its own.
    public let name: String

    /// Every tag.title the system has been seen to publish for this module.
    public let titleAliases: Set<String>

    /// The MenuBarAgent menu-extra title used as the Control Center governance
    /// key (e.g. com.apple.menuextra.airdrop), or nil when the module has no
    /// Control Center per-host preference.
    public let controlCenterMenuExtraTitle: String?

    /// The Control Center per-host preference key (e.g. AirDrop), or nil.
    public let controlCenterPrefKey: String?
}

// MARK: - SystemMenuBarModuleCatalog

/// The single registry of Apple system menu bar modules. The Control Center
/// mapping and the runtime kit's per-module tables both key off the name.
public enum SystemMenuBarModuleCatalog {
    /// Unifies the Control Center per-host keys (modules it hides itself with
    /// <key> -int <2|8>) and the titles the menu bar host publishes.
    public static let all: [SystemMenuBarModule] = [
        // Control-Center-governable modules.
        SystemMenuBarModule(
            name: "AirDrop",
            titleAliases: [],
            controlCenterMenuExtraTitle: "com.apple.menuextra.airdrop",
            controlCenterPrefKey: "AirDrop"
        ),
        SystemMenuBarModule(
            name: "Bluetooth",
            titleAliases: ["Bluetooth", "com.apple.menuextra.bluetooth"],
            controlCenterMenuExtraTitle: "com.apple.menuextra.bluetooth",
            controlCenterPrefKey: "Bluetooth"
        ),
        SystemMenuBarModule(
            name: "WiFi",
            titleAliases: ["WiFi", "Wi-Fi", "com.apple.menuextra.wifi"],
            controlCenterMenuExtraTitle: "com.apple.menuextra.wifi",
            controlCenterPrefKey: "WiFi"
        ),
        SystemMenuBarModule(
            name: "NowPlaying",
            titleAliases: [],
            controlCenterMenuExtraTitle: "com.apple.menuextra.now-playing",
            controlCenterPrefKey: "NowPlaying"
        ),
        SystemMenuBarModule(
            name: "UserSwitcher",
            titleAliases: [],
            controlCenterMenuExtraTitle: "com.apple.menuextra.user",
            controlCenterPrefKey: "UserSwitcher"
        ),
        SystemMenuBarModule(
            name: "FocusModes",
            titleAliases: [],
            controlCenterMenuExtraTitle: "com.apple.menuextra.focusmode",
            controlCenterPrefKey: "FocusModes"
        ),
        SystemMenuBarModule(
            name: "Sound",
            titleAliases: ["Sound", "Volume", "com.apple.menuextra.sound", "com.apple.menuextra.volume"],
            controlCenterMenuExtraTitle: "com.apple.menuextra.sound",
            controlCenterPrefKey: "Sound"
        ),
        // Modules with no Control Center per-host preference.
        SystemMenuBarModule(
            name: "Battery",
            titleAliases: ["Battery", "com.apple.menuextra.battery"],
            controlCenterMenuExtraTitle: nil,
            controlCenterPrefKey: nil
        ),
        SystemMenuBarModule(
            // The mic and camera indicator. Without this entry, writes went to
            // a status: row the agent ignores instead of module:AudioVideoModule.
            name: "AudioVideoModule",
            titleAliases: ["AudioVideoModule", "com.apple.menuextra.audiovideo"],
            controlCenterMenuExtraTitle: nil,
            controlCenterPrefKey: nil
        ),
        SystemMenuBarModule(
            name: "Clock",
            titleAliases: ["Clock", "com.apple.menuextra.clock"],
            controlCenterMenuExtraTitle: nil,
            controlCenterPrefKey: nil
        ),
        SystemMenuBarModule(
            name: "Displays",
            titleAliases: ["Displays", "Display", "com.apple.menuextra.display", "com.apple.menuextra.displays"],
            controlCenterMenuExtraTitle: nil,
            controlCenterPrefKey: nil
        ),
        SystemMenuBarModule(
            name: "Keyboard",
            titleAliases: ["Keyboard", "com.apple.menuextra.keyboard"],
            controlCenterMenuExtraTitle: nil,
            controlCenterPrefKey: nil
        ),
        SystemMenuBarModule(
            name: "ScreenMirroring",
            titleAliases: ["ScreenMirroring", "Screen Mirroring", "com.apple.menuextra.screenmirroring"],
            controlCenterMenuExtraTitle: nil,
            controlCenterPrefKey: nil
        ),
        SystemMenuBarModule(
            name: "Timer",
            // Keyed as module:Timer on macOS 27. The menu-extra id is guessed
            // from the naming convention, not verified by an AX walk.
            titleAliases: ["Timer", "com.apple.menuextra.timer"],
            controlCenterMenuExtraTitle: nil,
            controlCenterPrefKey: nil
        ),
        SystemMenuBarModule(
            name: "ControlCenter",
            titleAliases: ["BentoBox-0", "ControlCenter", "com.apple.menuextra.controlcenter"],
            controlCenterMenuExtraTitle: nil,
            controlCenterPrefKey: nil
        ),
    ]

    /// Menu-extra title to Control Center per-host preference key.
    public static let controlCenterKeysByMenuExtraTitle: [String: String] = {
        var map = [String: String]()
        for module in all {
            if let menuExtra = module.controlCenterMenuExtraTitle, let prefKey = module.controlCenterPrefKey {
                map[menuExtra] = prefKey
            }
        }
        return map
    }()

    /// The catalog's stable name for title, which may be an AX title, alias,
    /// menu-extra identifier, or Control Center preference key.
    public static func moduleName(matching title: String) -> String? {
        module(matching: title)?.name
    }

    /// The catalog entry title names, in any of the forms
    /// moduleName(matching:) documents. The only place the match is spelled out.
    public static func module(matching title: String) -> SystemMenuBarModule? {
        guard !title.isEmpty else { return nil }
        return all.first { module in
            module.name == title ||
                module.titleAliases.contains(title) ||
                module.controlCenterMenuExtraTitle == title ||
                module.controlCenterPrefKey == title
        }
    }

    /// Whether title is one the system publishes for its clock module.
    public static func isClock(title: String) -> Bool {
        moduleName(matching: title) == "Clock"
    }

    /// Canonical preferred-position key for a MenuBarAgent-hosted Apple module
    /// (e.g. module:WiFi).
    public static func trailingPositionsModuleKey(forTitle title: String) -> String {
        // AX publishes menu-extra ids, the agent sorts module: keys.
        // Display is persisted singular though its catalog name is plural.
        let catalogName = moduleName(matching: title) ?? title
        let persistedName = catalogName == "Displays" ? "Display" : catalogName
        return "module:\(persistedName)"
    }
}
