//
//  MenuBarLayoutGroupsSection.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Manages item groups from Settings.
///
/// This is the discoverable surface, and the only path that works from the
/// keyboard or with VoiceOver. It edits the persisted store, so it lists user
/// groups plus the automatic same-bundle clusters currently resolved against
/// live items; automatic clusters have no record until the user touches one.
struct MenuBarLayoutGroupsSection: View {
    @Environment(AppState.self) private var appState: AppState
    @State private var editingNames = [UUID: String]()
    @State private var primarySelection: String?
    @State private var secondarySelection: String?

    /// Live items indexed by unique identifier, rebuilt once per item-cache
    /// update rather than on every access.
    @State private var liveItemsByID = [String: MenuBarItem]()

    /// One row of the list: a stored user group, or an automatic same-bundle
    /// cluster resolved against the live items.
    private struct GroupRow: Identifiable {
        let origin: MenuBarItemGroupOrigin
        /// The stored name of a user group, blank when it has none, or the
        /// derived name of an automatic cluster.
        let name: String
        let memberIdentifiers: [String]

        var id: String {
            origin.description
        }
    }

    private var groupRows: [GroupRow] {
        let manager = appState.itemGroupManager

        // User groups come straight from the store, so one whose app is not
        // running keeps its row — and its "not running" members — instead of
        // vanishing until the app is launched again.
        var rows = manager.groupSet.groups.map { group in
            GroupRow(
                origin: .user(group.id),
                name: group.name ?? "",
                memberIdentifiers: group.memberIdentifiers
            )
        }

        // Automatic clusters have no stored record at all, so the only way to
        // list them is to resolve them against the live items.
        let items = allLiveItems
        for group in manager.resolvedGroups(for: items) where !group.origin.isUserAuthored {
            rows.append(
                GroupRow(
                    origin: group.origin,
                    name: manager.displayName(for: group, in: items),
                    memberIdentifiers: group.memberIndices.compactMap {
                        items.indices.contains($0) ? items[$0].uniqueIdentifier : nil
                    }
                )
            )
        }

        return rows
    }

    private var allLiveItems: [MenuBarItem] {
        MenuBarSection.Name.allCases.flatMap { appState.itemManager.itemCache.managedItems(for: $0) }
    }

    private var groupableItems: [MenuBarItem] {
        allLiveItems.filter { MenuBarItemGrouping.isGroupable($0.tag) }
    }

    var body: some View {
        IceSection("Item groups") {
            let rows = groupRows
            if rows.isEmpty {
                Text("Pick two items below to group them. Grouped items always move together.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(rows) { row in
                    groupRow(row)
                    if row.id != rows.last?.id {
                        Divider()
                    }
                }
                Text("Groups always move together: drag any member in the bars above and the whole group follows.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            createGroupControls
        }
        .onChange(of: appState.itemManager.itemCache, initial: true) {
            rebuildLiveItems()
        }
    }

    private var createGroupControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("First item") {
                Picker("First item", selection: $primarySelection) {
                    Text("Choose an item").tag(String?.none)
                    ForEach(groupableItems, id: \.uniqueIdentifier) { item in
                        Text(item.displayName).tag(String?.some(item.uniqueIdentifier))
                    }
                }
                .labelsHidden()
            }
            LabeledContent("Second item") {
                Picker("Second item", selection: $secondarySelection) {
                    Text("Choose an item").tag(String?.none)
                    ForEach(groupableItems, id: \.uniqueIdentifier) { item in
                        Text(item.displayName).tag(String?.some(item.uniqueIdentifier))
                    }
                }
                .labelsHidden()
            }
            Button("Create Group") {
                createGroup()
            }
            .disabled(primarySelection == nil || secondarySelection == nil || primarySelection == secondarySelection)
            .annotation("Grouped items stay adjacent: drag any member and the whole group moves with it.")
        }
    }

    private func createGroup() {
        guard let firstID = primarySelection, let secondID = secondarySelection, firstID != secondID else {
            return
        }
        let items = [firstID, secondID].compactMap { liveItemsByID[$0] }
        guard appState.itemGroupManager.createGroup(name: nil, items: items) != nil else {
            return
        }
        primarySelection = nil
        secondarySelection = nil
    }

    private func groupRow(_ row: GroupRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if case let .user(id) = row.origin {
                    TextField(
                        "Group name",
                        text: Binding(
                            get: { editingNames[id] ?? row.name },
                            set: { editingNames[id] = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitName(forGroupWithID: id) }
                } else {
                    // An automatic cluster is re-derived from live tags every
                    // layout pass and has no record to rename or edit, so it
                    // is listed read-only. Ungroup still applies: that records
                    // a suppression for the bundle.
                    Text(row.name)
                    Text("automatic")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Ungroup", role: .destructive) {
                    appState.itemGroupManager.ungroup(row.origin)
                }
            }

            ForEach(row.memberIdentifiers, id: \.self) { identifier in
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
                    if row.origin.isUserAuthored {
                        Button {
                            removeMember(identifier)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove from group")
                    }
                }
                .padding(.leading, 12)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Helpers

    private func rebuildLiveItems() {
        let items = allLiveItems
        liveItemsByID = Dictionary(items.map { ($0.uniqueIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func liveItem(_ identifier: String) -> MenuBarItem? {
        liveItemsByID[identifier]
    }

    private func memberName(_ identifier: String) -> String {
        guard let item = liveItem(identifier) else {
            return identifier
        }
        return item.displayName
    }

    private func commitName(forGroupWithID id: UUID) {
        let name = editingNames[id] ?? ""
        appState.itemGroupManager.rename(.user(id), to: name, members: [])
        editingNames.removeValue(forKey: id)
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
