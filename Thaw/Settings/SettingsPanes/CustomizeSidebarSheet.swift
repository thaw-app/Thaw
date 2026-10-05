//
//  CustomizeSidebarSheet.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Lets the user hide sidebar destinations they don't use.
///
/// Every destination is listed with an on/off toggle. Hidden panes leave the
/// sidebar but stay reachable via search and thaw://, exactly as absorbed
/// panes already are. The basics can't all be hidden (the sidebar must keep
/// at least one row), and the currently-selected pane can't be hidden (so
/// hiding never orphans the detail).
struct CustomizeSidebarSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    private var navigationState: AppNavigationState {
        appState.navigationState
    }

    private var hidden: Set<String> {
        navigationState.hiddenSidebarPanes
    }

    private var visibleCount: Int {
        SettingsSidebarPanes.all.count - hidden.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(minWidth: 360, idealWidth: 360, minHeight: 460, idealHeight: 460)
        // The sheet has nothing to cancel, so Esc means Done too.
        .onExitCommand { dismiss() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Customize Sidebar")
                .font(.headline)
            Text("Hide destinations you don't use. Hidden panes stay reachable through search.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(SettingsSidebarPanes.all, id: \.self) { pane in
                    row(for: pane)
                    Divider().opacity(0.4)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func row(for pane: SettingsNavigationIdentifier) -> some View {
        let isHidden = hidden.contains(pane.rawValue)
        let isSelected = navigationState.settingsNavigationIdentifier == pane
        // The currently-selected pane can't be hidden (would orphan the detail).
        // The last visible pane can't be hidden (sidebar must keep one row).
        let isLocked = isSelected || (visibleCount <= 1 && !isHidden)

        HStack(spacing: 12) {
            pane.iconResource.view
                .frame(width: 20, height: 20)
            Text(pane.localized)
                .lineLimit(1)
            Spacer()
            if isLocked {
                if isSelected {
                    Text("Current")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Toggle(pane.localized, isOn: Binding(
                    get: { !isHidden },
                    set: { isVisible in
                        if isVisible {
                            navigationState.hiddenSidebarPanes.remove(pane.rawValue)
                        } else {
                            navigationState.hiddenSidebarPanes.insert(pane.rawValue)
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .opacity(isLocked && !isSelected ? 0.5 : 1)
        .help(isLocked && !isSelected
            ? "At least one destination must stay visible"
            : isSelected
            ? "Hide this from a different destination first"
            : "")
    }

    private var footer: some View {
        HStack {
            Text("\(visibleCount) of \(SettingsSidebarPanes.all.count) visible")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.glassProminent)
            .controlSize(.regular)
        }
        .padding(16)
    }
}
