//
//  SettingsURIAction+Hotkey.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

extension SettingsURIAction {
    /// The hotkey action this URL runs, nil for the two that open a window or overlay of their own.
    nonisolated var hotkeyAction: HotkeyAction? {
        switch self {
        case .toggleHidden: .toggleHiddenSection
        case .toggleAlwaysHidden: .toggleAlwaysHiddenSection
        case .toggleSwap: .toggleSwap
        case .search: .searchMenuBarItems
        case .toggleApplicationMenus: .toggleApplicationMenus
        case .toggleZenMode: .toggleZenMode
        case .toggleLayoutEditor: .toggleLayoutEditor
        case .openSettings, .itemHints: nil
        }
    }
}
