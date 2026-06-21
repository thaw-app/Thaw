//
//  HotkeyAction.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

enum HotkeyAction: String, Codable, CaseIterable {
    // Menu Bar Sections
    case toggleHiddenSection = "ToggleHiddenSection"
    case toggleAlwaysHiddenSection = "ToggleAlwaysHiddenSection"

    /// Menu Bar Items
    case searchMenuBarItems = "SearchMenuBarItems"

    // Other
    case enableIceBar = "EnableIceBar"
    case toggleApplicationMenus = "ToggleApplicationMenus"

    /// Used by profile hotkeys, action is handled externally.
    case profileApply = "ProfileApply"

    /// Used by per-item hotkeys, action is handled externally.
    case openMenuBarItem = "OpenMenuBarItem"

    /// Actions that should appear in the Hotkeys settings pane as fixed,
    /// singleton recorders. Dynamic per-profile and per-item hotkeys are
    /// created separately and are excluded here.
    static var settingsActions: [HotkeyAction] {
        allCases.filter { $0 != .profileApply && $0 != .openMenuBarItem }
    }

    @MainActor
    func perform(appState: AppState) {
        switch self {
        case .toggleHiddenSection:
            guard let section = appState.menuBarManager.section(withName: .hidden) else {
                return
            }
            section.toggle(triggeredByHotkey: true)
            // Prevent the section from automatically rehiding after mouse movement.
            if !section.isHidden {
                appState.menuBarManager.showOnHoverAllowed = false
            }
        case .toggleAlwaysHiddenSection:
            guard let section = appState.menuBarManager.section(withName: .alwaysHidden) else {
                return
            }
            section.toggle(triggeredByHotkey: true)
            // Prevent the section from automatically rehiding after mouse movement.
            if !section.isHidden {
                appState.menuBarManager.showOnHoverAllowed = false
            }
        case .searchMenuBarItems:
            appState.menuBarManager.searchPanel.toggle()
        case .enableIceBar:
            appState.settings.displaySettings.toggleIceBarForActiveDisplay()
        case .toggleApplicationMenus:
            appState.menuBarManager.toggleApplicationMenus()
        case .profileApply:
            // Handled externally by ProfileManager's custom registration.
            break
        case .openMenuBarItem:
            // Handled externally by MenuBarManager's per-item registration.
            break
        }
    }
}
