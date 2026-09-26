//
//  HotkeyAction+Perform.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Carries out a hotkey action against the live app.
///
/// Split from ``HotkeyAction`` because every branch drives a live menu bar,
/// which unit tests lack. New decision logic belongs in the tested file.
extension HotkeyAction {
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
        case .toggleAutoRehide:
            let general = appState.settings.general
            general.autoRehide.toggle()
            // The toggle has no visible effect until the next reveal, so
            // confirm the new state with a notification.
            appState.userNotificationManager.requestAuthorization()
            appState.userNotificationManager.addRequest(
                with: .hotkeyToggleFeedback,
                title: general.autoRehide
                    ? String(localized: "Automatic rehiding is on")
                    : String(localized: "Automatic rehiding is off"),
                body: ""
            )
        case .toggleZenMode:
            appState.menuBarManager.toggleZenMode()
            let isActive = appState.menuBarManager.isZenModeActive
            appState.userNotificationManager.requestAuthorization()
            appState.userNotificationManager.addRequest(
                with: .hotkeyToggleFeedback,
                title: isActive
                    ? String(localized: "Zen mode is on")
                    : String(localized: "Zen mode is off"),
                body: ""
            )
        case .profileApply:
            // Handled externally by ProfileManager's custom registration.
            break
        case .openMenuBarItem:
            // Handled externally by MenuBarManager's per-item registration.
            break
        }
    }
}
