//
//  SystemMenuBarModuleCatalog.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - SystemMenuBarModule

/// A single Apple-owned menu bar module and the identifiers each subsystem uses
/// to address it. Different pipelines key off different things — Control Center
/// governance matches a menu-extra title, assessment-index concealment matches
/// the live `tag.title` — so both are recorded here rather than duplicated per
/// subsystem.
public struct SystemMenuBarModule: Equatable, Sendable {
    /// Stable identifier for diagnostics and tests; never used as a runtime
    /// match key.
    public let name: String

    /// Every `tag.title` that identifies this module for `MBSystemItemIdentifier`
    /// (assessment-index) concealment. Empty when the module has no index.
    public let assessmentTitleAliases: Set<String>

    /// The module's `MBSystemItemIdentifier` raw value (0...8), or nil when the
    /// assessment allowlist can't address it individually (e.g. AirDrop, Focus).
    public let assessmentSystemItemID: Int?

    /// The MenuBarAgent menu-extra title used as the Control Center governance
    /// key (e.g. `com.apple.menuextra.airdrop`), or nil when the module has no
    /// Control Center per-host preference.
    public let controlCenterMenuExtraTitle: String?

    /// The Control Center per-host preference key (e.g. `AirDrop`), or nil.
    public let controlCenterPrefKey: String?
}

// MARK: - SystemMenuBarModuleCatalog

/// The single registry of Apple system menu bar modules. Adding support for a
/// new module means adding one ``SystemMenuBarModule`` here — the Control Center
/// mapping (``ControlCenterModuleManager``) and the assessment-index mapping
/// (``AssessmentModeBackend``) both derive from this list.
public enum SystemMenuBarModuleCatalog {
    /// All known modules.
    ///
    /// Sources this catalog unifies:
    ///   * Control Center per-host keys — the `<key> -int <2|8>` modules Control
    ///     Center hides on its own (AirDrop, Bluetooth, Wi-Fi, Now Playing, User
    ///     switcher, Focus).
    ///   * `MBSystemItemIdentifier` raw values 0...8 — the assessment-mode
    ///     allowlist indices (battery … the primary BentoBox).
    ///
    /// Bluetooth and Wi-Fi appear in both, so they carry both sets of fields.
    public static let all: [SystemMenuBarModule] = [
        // Control-Center-governable modules (some also assessment-indexable).
        SystemMenuBarModule(
            name: "AirDrop",
            assessmentTitleAliases: [],
            assessmentSystemItemID: nil,
            controlCenterMenuExtraTitle: "com.apple.menuextra.airdrop",
            controlCenterPrefKey: "AirDrop"
        ),
        SystemMenuBarModule(
            name: "Bluetooth",
            assessmentTitleAliases: ["Bluetooth", "com.apple.menuextra.bluetooth"],
            assessmentSystemItemID: 1,
            controlCenterMenuExtraTitle: "com.apple.menuextra.bluetooth",
            controlCenterPrefKey: "Bluetooth"
        ),
        SystemMenuBarModule(
            name: "WiFi",
            assessmentTitleAliases: ["WiFi", "Wi-Fi", "com.apple.menuextra.wifi"],
            assessmentSystemItemID: 6,
            controlCenterMenuExtraTitle: "com.apple.menuextra.wifi",
            controlCenterPrefKey: "WiFi"
        ),
        SystemMenuBarModule(
            name: "NowPlaying",
            assessmentTitleAliases: [],
            assessmentSystemItemID: nil,
            controlCenterMenuExtraTitle: "com.apple.menuextra.now-playing",
            controlCenterPrefKey: "NowPlaying"
        ),
        SystemMenuBarModule(
            name: "UserSwitcher",
            assessmentTitleAliases: [],
            assessmentSystemItemID: nil,
            controlCenterMenuExtraTitle: "com.apple.menuextra.user",
            controlCenterPrefKey: "UserSwitcher"
        ),
        SystemMenuBarModule(
            name: "FocusModes",
            assessmentTitleAliases: [],
            assessmentSystemItemID: nil,
            controlCenterMenuExtraTitle: "com.apple.menuextra.focusmode",
            controlCenterPrefKey: "FocusModes"
        ),
        // Assessment-index-only modules (no Control Center per-host preference).
        SystemMenuBarModule(
            name: "Battery",
            assessmentTitleAliases: ["Battery"],
            assessmentSystemItemID: 0,
            controlCenterMenuExtraTitle: nil,
            controlCenterPrefKey: nil
        ),
        SystemMenuBarModule(
            name: "Clock",
            assessmentTitleAliases: ["Clock", "com.apple.menuextra.clock"],
            assessmentSystemItemID: 2,
            controlCenterMenuExtraTitle: nil,
            controlCenterPrefKey: nil
        ),
        SystemMenuBarModule(
            name: "Displays",
            assessmentTitleAliases: ["Displays", "Display", "com.apple.menuextra.display", "com.apple.menuextra.displays"],
            assessmentSystemItemID: 3,
            controlCenterMenuExtraTitle: nil,
            controlCenterPrefKey: nil
        ),
        SystemMenuBarModule(
            name: "Keyboard",
            assessmentTitleAliases: ["Keyboard", "com.apple.menuextra.keyboard"],
            assessmentSystemItemID: 4,
            controlCenterMenuExtraTitle: nil,
            controlCenterPrefKey: nil
        ),
        SystemMenuBarModule(
            name: "Sound",
            assessmentTitleAliases: ["Sound", "Volume", "com.apple.menuextra.sound", "com.apple.menuextra.volume"],
            assessmentSystemItemID: 5,
            controlCenterMenuExtraTitle: nil,
            controlCenterPrefKey: nil
        ),
        SystemMenuBarModule(
            name: "ScreenMirroring",
            assessmentTitleAliases: ["ScreenMirroring", "Screen Mirroring", "com.apple.menuextra.screenmirroring"],
            assessmentSystemItemID: 7,
            controlCenterMenuExtraTitle: nil,
            controlCenterPrefKey: nil
        ),
        SystemMenuBarModule(
            name: "ControlCenter",
            assessmentTitleAliases: ["BentoBox-0", "ControlCenter", "com.apple.menuextra.controlcenter"],
            assessmentSystemItemID: 8,
            controlCenterMenuExtraTitle: nil,
            controlCenterPrefKey: nil
        ),
    ]

    /// Menu-extra title → Control Center per-host preference key, for every
    /// Control-Center-governable module.
    public static let controlCenterKeysByMenuExtraTitle: [String: String] = {
        var map = [String: String]()
        for module in all {
            if let menuExtra = module.controlCenterMenuExtraTitle, let prefKey = module.controlCenterPrefKey {
                map[menuExtra] = prefKey
            }
        }
        return map
    }()

    /// The `MBSystemItemIdentifier` raw value for the given live item title, or
    /// nil when no assessment-indexable module claims it.
    public static func assessmentSystemItemID(forTitle title: String) -> Int? {
        for module in all where module.assessmentTitleAliases.contains(title) {
            return module.assessmentSystemItemID
        }
        return nil
    }

    /// User-facing module name when `title` matches a known Apple system item.
    ///
    /// Accepts live AX titles (`Wi-Fi`), assessment aliases (`Clock`), menu-extra
    /// identifiers (`com.apple.menuextra.wifi`), and Control Center preference
    /// keys (`WiFi`). Returns the catalog's stable `name` (e.g. `WiFi`).
    public static func moduleName(matching title: String) -> String? {
        guard !title.isEmpty else { return nil }
        for module in all {
            if module.name == title ||
                module.assessmentTitleAliases.contains(title) ||
                module.controlCenterMenuExtraTitle == title ||
                module.controlCenterPrefKey == title
            {
                return module.name
            }
        }
        return nil
    }

    /// Canonical ``TrailingItemPreferredPositions`` key for a MenuBarAgent-hosted
    /// Apple module (e.g. `module:WiFi`).
    public static func trailingPositionsModuleKey(forTitle title: String) -> String {
        // AX publishes menu-extra identifiers while MenuBarAgent sorts the
        // corresponding `module:` key. Display is the one known module whose
        // persisted key is singular even though its catalog name is plural.
        let catalogName = moduleName(matching: title) ?? title
        let persistedName = catalogName == "Displays" ? "Display" : catalogName
        return "module:\(persistedName)"
    }
}
