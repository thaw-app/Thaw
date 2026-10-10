//
//  MenuBarLayoutGroupsSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawUI

/// Manages item groups from Settings, the keyboard and VoiceOver path to what
/// the layout bar's right-click menu does. Lists user groups only: automatic
/// same-bundle clusters have no stored record until the user touches one.
struct MenuBarLayoutGroupsSection: View {
    @Environment(AppState.self) private var appState
    @State private var editingNames = [UUID: String]()
    /// Indexed once per membership change, since every keystroke in the name
    /// fields re-runs body and a scan per row would be quadratic.
    @State private var liveItemsByID = [String: MenuBarItem]()

    private var groups: [MenuBarItemGroup] {
        appState.itemGroupManager.groupSet.groups
    }

    var body: some View {
        ThawSection("Item groups") {
            if groups.isEmpty {
                // A compact row, not a tall empty state: the bar above matters more.
                Text("No item groups. Right-click an item in the bars above to group it with another.")
                    .font(ThawType.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(groups) { group in
                    groupRow(group)
                        .contextMenu {
                            Button(group.isCollapsed ? "Expand" : "Collapse") {
                                appState.itemGroupManager.setCollapsed(
                                    !group.isCollapsed,
                                    for: .user(group.id),
                                    members: []
                                )
                            }
                            Button(appState.groupFolders.isFolder(.user(group.id)) ? "Stop Showing as Folder" : "Show as Folder") {
                                toggleFolder(group)
                            }
                            Divider()
                            Button("Ungroup", role: .destructive) {
                                appState.itemGroupManager.ungroup(.user(group.id))
                            }
                        }
                    if group.id != groups.last?.id {
                        Divider()
                    }
                }
                Text("Groups always move and hide together. Drag any member in the bars above to move the whole group.")
                    .font(ThawType.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Keyed on tags, not the cache, so a quitting app still updates its
        // member but an AX walk nudging bounds does not rebuild the index.
        .onChange(of: appState.itemManager.managedItemTags, initial: true) {
            rebuildLiveItems()
        }
    }

    /// The folder icon's symbol and color. No color draws it in the menu
    /// bar's own ink, like every other item.
    private func folderStyleRow(_ group: MenuBarItemGroup) -> some View {
        let folders = appState.groupFolders
        let style = folders.style(for: group.id)
        return HStack(spacing: ThawSpacing.base) {
            Text("Folder icon")
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("Folder icon", selection: Binding(
                get: { style.symbol },
                set: { symbol in
                    var updated = style
                    updated.symbol = symbol
                    folders.setStyle(updated, for: group.id)
                }
            )) {
                ForEach(GroupFolders.Style.symbols, id: \.self) { symbol in
                    Label {
                        Text(verbatim: symbol)
                    } icon: {
                        Image(systemName: symbol)
                    }
                    .labelStyle(.iconOnly)
                    .tag(symbol)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            Toggle("Color", isOn: Binding(
                get: { style.color != nil },
                set: { isOn in
                    var updated = style
                    updated.color = isOn ? .systemBlue : nil
                    folders.setStyle(updated, for: group.id)
                }
            ))
            if let color = style.color {
                ColorPicker(
                    "Folder color",
                    selection: Binding(
                        get: { Color(nsColor: color) },
                        set: { newColor in
                            var updated = style
                            updated.color = NSColor(newColor)
                            folders.setStyle(updated, for: group.id)
                        }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
            }
            Spacer()
        }
        .padding(.leading, 12)
    }

    private func toggleFolder(_ group: MenuBarItemGroup) {
        let members = group.memberIdentifiers.compactMap(liveItem)
        appState.groupFolders.setFolder(
            !appState.groupFolders.isFolder(.user(group.id)),
            for: .user(group.id),
            members: members
        )
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
                .buttonStyle(.settingsGlass)
                Toggle("Folder", isOn: Binding(
                    get: { appState.groupFolders.isFolder(.user(group.id)) },
                    set: { _ in toggleFolder(group) }
                ))
                .help("Keeps the group's items in Hidden and puts a folder icon in the menu bar that opens them.")
                Button("Ungroup", role: .destructive) {
                    appState.itemGroupManager.ungroup(.user(group.id))
                }
                .buttonStyle(.settingsGlass)
            }

            if appState.groupFolders.isFolder(.user(group.id)) {
                folderStyleRow(group)
            }

            ForEach(group.memberIdentifiers, id: \.self) { identifier in
                HStack(spacing: 8) {
                    Text(memberName(identifier))
                        .font(.callout)
                        .foregroundStyle(liveItem(identifier) == nil ? .secondary : .primary)
                    if liveItem(identifier) == nil {
                        // A quit app keeps its membership, so say why it looks inactive.
                        ThawBadge("not running")
                    }
                    Spacer()
                    Button {
                        removeMember(identifier)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Remove from group")
                    .accessibilityLabel("Remove \(memberName(identifier)) from group")
                }
                .padding(.leading, 12)
                .contextMenu {
                    Button("Remove from Group", role: .destructive) {
                        removeMember(identifier)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Helpers

    private func rebuildLiveItems() {
        let items = MenuBarSection.Name.allCases.flatMap {
            appState.itemManager.managedItems(for: $0)
        }
        // First occurrence wins, matching a search over the flattened array.
        liveItemsByID = Dictionary(items.map { ($0.uniqueIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func liveItem(_ identifier: String) -> MenuBarItem? {
        liveItemsByID[identifier]
    }

    private func memberName(_ identifier: String) -> String {
        guard let item = liveItem(identifier) else {
            return identifier
        }
        // item.displayName hits Defaults and NSRunningApplication per read, and
        // synchronous NSWorkspace lookups for quit apps; this path is memoized.
        return MenuBarItemDisplayName.displayName(for: item)
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
