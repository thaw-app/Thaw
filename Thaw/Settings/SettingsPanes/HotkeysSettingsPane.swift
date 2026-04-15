//
//  HotkeysSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct HotkeysSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings: HotkeysSettings

    var body: some View {
        IceForm {
            IceSection("Menu Bar Sections") {
                hotkeyRecorder(forSection: .hidden)
                hotkeyRecorder(forSection: .alwaysHidden)
            }
            IceSection("Menu Bar Items") {
                hotkeyRecorder(forAction: .searchMenuBarItems)
            }
            if !appState.profileManager.profiles.isEmpty {
                IceSection("Profiles") {
                    ForEach(appState.profileManager.profiles) { meta in
                        profileHotkeyRecorder(for: meta)
                    }
                }
            }
            IceSection("Other") {
                hotkeyRecorder(forAction: .enableIceBar)
                hotkeyRecorder(forAction: .toggleApplicationMenus)
            }
        }
    }

    @ViewBuilder
    private func hotkeyRecorder(forAction action: HotkeyAction) -> some View {
        if let hotkey = settings.hotkey(withAction: action) {
            HotkeyRecorder(hotkey: hotkey) {
                switch action {
                case .toggleHiddenSection:
                    Text("Toggle the hidden section")
                case .toggleAlwaysHiddenSection:
                    Text("Toggle the always-hidden section")
                case .searchMenuBarItems:
                    Text("Search menu bar items")
                case .enableIceBar:
                    Text("Enable the \(Constants.displayName) Bar")
                case .toggleApplicationMenus:
                    Text("Toggle application menus")
                case .profileApply:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder
    private func profileHotkeyRecorder(for meta: ProfileMetadata) -> some View {
        if let hotkey = appState.profileManager.profileHotkeys[meta.id] {
            HotkeyRecorder(hotkey: hotkey) {
                Text(meta.name)
            }
        }
    }

    @ViewBuilder
    private func hotkeyRecorder(forSection name: MenuBarSection.Name) -> some View {
        if appState.menuBarManager.section(withName: name)?.isEnabled == true {
            if case .hidden = name {
                hotkeyRecorder(forAction: .toggleHiddenSection)
            } else if case .alwaysHidden = name {
                hotkeyRecorder(forAction: .toggleAlwaysHiddenSection)
            }
        }
    }
}
