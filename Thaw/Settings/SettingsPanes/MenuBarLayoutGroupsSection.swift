//
//  MenuBarLayoutGroupsSection.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI

/// Manages item groups from Settings.
///
/// The layout bar's right-click menu is the direct-manipulation surface; this is
/// the discoverable one, and the only path that works from the keyboard or with
/// VoiceOver. It edits the persisted store, so it lists *user* groups only —
/// automatic same-bundle clusters have no record until the user touches one.
struct MenuBarLayoutGroupsSection: View {
    @EnvironmentObject private var appState: AppState
    @State private var editingNames = [UUID: String]()

    private var groups: [MenuBarItemGroup] {
        appState.itemGroupManager.groupSet.groups
    }

    var body: some View {
        // Grouping is macOS 27-only; on the legacy backend every edit would be
        // a silent no-op, so the section is absent rather than inert.
        if !MenuBarBackendProvider.current.supportsLegacySectionHiding {
            IceSection("Item groups") {
                if groups.isEmpty {
                    Text("Right-click an item in the layout bars above to group it with another. Grouped items always move and hide together.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(groups) { group in
                        groupRow(group)
                        if group.id != groups.last?.id {
                            Divider()
                        }
                    }
                    Text("Groups always move and hide together. Drag any member in the bars above to move the whole group.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func groupRow(_ group: MenuBarItemGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(
                    "Group name",
                    text: Binding(
                        get: { editingNames[group.id] ?? group.name ?? "" },
                        set: { editingNames[group.id] = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitName(for: group) }

                Spacer()

                Button(group.isCollapsed ? "Expand" : "Collapse") {
                    appState.itemGroupManager.setCollapsed(
                        !group.isCollapsed,
                        for: .user(group.id),
                        members: []
                    )
                }
                Button("Ungroup", role: .destructive) {
                    appState.itemGroupManager.ungroup(.user(group.id))
                }
            }

            ForEach(group.memberIdentifiers, id: \.self) { identifier in
                HStack(spacing: 8) {
                    Text(memberName(identifier))
                        .font(.callout)
                        .foregroundStyle(liveItem(identifier) == nil ? .secondary : .primary)
                    if liveItem(identifier) == nil {
                        // A quit app keeps its membership — losing a group
                        // because an app was closed would be the worst possible
                        // failure here — so say why it looks inactive.
                        Text("not running")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        removeMember(identifier)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove from group")
                }
                .padding(.leading, 12)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Helpers

    private var allItems: [MenuBarItem] {
        MenuBarSection.Name.allCases.flatMap {
            appState.itemManager.itemCache.managedItems(for: $0)
        }
    }

    private func liveItem(_ identifier: String) -> MenuBarItem? {
        allItems.first { $0.uniqueIdentifier == identifier }
    }

    private func memberName(_ identifier: String) -> String {
        liveItem(identifier)?.displayName ?? identifier
    }

    private func commitName(for group: MenuBarItemGroup) {
        let name = editingNames[group.id] ?? ""
        appState.itemGroupManager.rename(.user(group.id), to: name, members: [])
        editingNames.removeValue(forKey: group.id)
    }

    private func removeMember(_ identifier: String) {
        guard let item = liveItem(identifier) else {
            // No live item to hand the manager, so edit the store directly by
            // rebuilding the group without this member.
            appState.itemGroupManager.removeMemberIdentifier(identifier)
            return
        }
        appState.itemGroupManager.removeMember(item)
    }
}
