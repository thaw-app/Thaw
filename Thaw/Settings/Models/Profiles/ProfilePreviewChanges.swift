//
//  ProfilePreviewChanges.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// What a profile preview lists besides moves: changed settings, and every
/// other part of the setup applying it would replace.
@MainActor
enum ProfilePreviewChanges {
    /// One part of the setup a profile replaces, encoded for comparison.
    struct Area {
        let key: String
        let label: String
        let current: Data?
        let profile: Data?
    }

    static func settingChanges(of profile: Profile, appState: AppState) -> [ProfileLayoutDiff.SettingChange] {
        let advanced = AdvancedSettingsSnapshot.capture(from: appState.settings)
        return ProfileLayoutDiff.settingChanges(current: GeneralSettingsSnapshot.capture(from: appState.settings), profile: profile.generalSettings)
            + ProfileLayoutDiff.settingChanges(
                current: advanced,
                profile: profile.advancedSettings.merged(onto: advanced, storesAlwaysHiddenSection: profile.storesAlwaysHiddenSection)
            )
            + changedAreas(areas(of: profile, appState: appState))
    }

    /// The areas whose saved form differs, in the order given.
    static func changedAreas(_ areas: [Area]) -> [ProfileLayoutDiff.SettingChange] {
        areas.filter { $0.current != $0.profile }.map { ProfileLayoutDiff.SettingChange(key: $0.key, label: $0.label) }
    }

    private static func areas(of profile: Profile, appState: AppState) -> [Area] {
        let display = appState.settings.displaySettings
        let shortcuts = HotkeyBindingStore.actions.rawBindings()
        let mergedShortcuts = ProfileHotkeyMerge.merged(current: shortcuts, profile: profile.hotkeys, knownActions: profile.hotkeyActions)
        let names = Defaults.dictionary(forKey: .menuBarItemCustomNames) as? [String: String] ?? [:]
        let itemShortcuts = HotkeyBindingStore.items.rawBindings()
        return [
            area("appearance", String(localized: "Appearance"), appState.appearanceManager.configuration, profile.appearanceConfiguration),
            area("shortcuts", String(localized: "Shortcuts"), shortcuts, mergedShortcuts),
            area("thawBarDisplays", String(localized: "Thaw Bar on each display"), display.configurations, profile.displayConfigurations),
            area("thawBarTemplate", String(localized: "Thaw Bar for new displays"), display.globalConfiguration, profile.globalDisplayConfiguration),
            area("groups", String(localized: "Item groups"), appState.itemGroupManager.snapshot(), profile.menuBarLayout.itemGroups ?? .empty),
            area("names", String(localized: "Item names"), names, profile.menuBarLayout.customNames),
            area("itemShortcuts", String(localized: "Item shortcuts"), itemShortcuts, profile.menuBarLayout.itemHotkeys ?? [:]),
        ]
    }

    private static func area(_ key: String, _ label: String, _ current: some Encodable, _ profile: some Encodable) -> Area {
        Area(key: "area.\(key)", label: label, current: encoded(current), profile: encoded(profile))
    }

    /// Sorted keys, so two equal dictionaries always encode the same.
    private static func encoded(_ value: some Encodable) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(value)
    }
}
