//
//  LayoutSelectionGrouping.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Grouping for several selected Layout items: a new group, joining a group, or a folder.
/// Like the single-item menu, it groups only items in one section, and only with that section's groups.
@MainActor
struct LayoutSelectionGrouping {
    /// Why the selection can't be grouped.
    enum Refusal: Equatable {
        case severalSections
        case tooFewGroupable
    }

    /// The selected items, left to right.
    let items: [MenuBarItem]
    /// Every item in the selection's section, left to right.
    let sectionItems: [MenuBarItem]
    let manager: MenuBarItemGroupManager
    let undoManager: UndoManager?
    /// Nil when the selection is in one section.
    let sectionRefusal: Refusal?

    init(items: [MenuBarItem], sectionItems: [MenuBarItem], manager: MenuBarItemGroupManager, undoManager: UndoManager?, isOneSection: Bool = true) {
        self.items = items
        self.sectionItems = sectionItems
        self.manager = manager
        self.undoManager = undoManager
        sectionRefusal = isOneSection ? nil : .severalSections
    }

    /// The grouping for the selection, or nil when nothing is selected.
    static func make(selection: LayoutSelectionModel, appState: AppState) -> LayoutSelectionGrouping? {
        let ids = selection.orderedItemIDs
        guard !ids.isEmpty else { return nil }
        let sections = selection.sections
        let section = sections.count == 1 ? sections.first : nil
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let sectionItems = section.map { LayoutDisplayedItems.items(in: $0, appState: appState, runningApplications: running) } ?? []
        let byID = Dictionary(appState.itemManager.managedItems.map { ($0.uniqueIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        return LayoutSelectionGrouping(
            items: ids.compactMap { byID[$0] },
            sectionItems: sectionItems,
            manager: appState.itemGroupManager,
            undoManager: appState.layoutUndo,
            isOneSection: section != nil
        )
    }

    private var groupable: [MenuBarItem] {
        items.filter { MenuBarItemGrouping.isGroupable($0.tag) }
    }

    private var groups: [ResolvedGroup] {
        manager.resolvedGroups(for: sectionItems)
    }

    private func members(of group: ResolvedGroup) -> [MenuBarItem] {
        group.memberIndices.compactMap { sectionItems.indices.contains($0) ? sectionItems[$0] : nil }
    }

    /// Why a new group can't be made, or nil when it can.
    var refusal: Refusal? {
        if let sectionRefusal {
            return sectionRefusal
        }
        return groupable.count < 2 ? .tooFewGroupable : nil
    }

    /// The group the selection is exactly, when it is one.
    var selectedGroup: ResolvedGroup? {
        let selected = Set(groupable.map(\.uniqueIdentifier))
        return groups.first { Set(members(of: $0).map(\.uniqueIdentifier)) == selected }
    }

    /// Whether Group Selected would make a group the selection isn't already.
    var canGroup: Bool {
        refusal == nil && selectedGroup == nil
    }

    /// The section's groups the selection could join: any not already holding every selected item.
    var joinableGroups: [ResolvedGroup] {
        guard sectionRefusal == nil, !groupable.isEmpty else { return [] }
        let selected = Set(groupable.map(\.uniqueIdentifier))
        return groups.filter { !selected.isSubset(of: Set(members(of: $0).map(\.uniqueIdentifier))) }
    }

    func name(of group: ResolvedGroup) -> String {
        manager.displayName(for: group, in: sectionItems)
    }

    /// Makes one group of the selection, taking its items out of the groups they were in.
    @discardableResult
    func group() -> MenuBarItemGroup? {
        guard canGroup else { return nil }
        var created: MenuBarItemGroup?
        LayoutEditUndo.editGroups(
            String(localized: "Group \(groupable.count) Items", comment: "Undo menu action name for grouping several selected Layout items"),
            manager: manager,
            undoManager: undoManager
        ) {
            created = manager.createGroup(name: nil, items: groupable)
        }
        return created
    }

    /// Adds the selection to group. An automatic cluster becomes a stored group first, as in the single-item menu.
    func add(to group: ResolvedGroup) {
        guard joinableGroups.contains(where: { $0.origin == group.origin }) else { return }
        let name = name(of: group)
        let joining = groupable
        LayoutEditUndo.editGroups(
            String(localized: "Add to \(name)"),
            manager: manager,
            undoManager: undoManager
        ) {
            switch group.origin {
            case let .user(id):
                for item in joining {
                    manager.add(item, to: id)
                }
            case .automatic:
                let existing = members(of: group)
                let ids = Set(existing.map(\.uniqueIdentifier))
                _ = manager.createGroup(name: name, items: existing + joining.filter { !ids.contains($0.uniqueIdentifier) })
            }
        }
    }

    /// Shows the selection as a folder, grouping it first when it isn't one group already. One undo step.
    func makeFolder(folders: GroupFolders) {
        guard refusal == nil else { return }
        undoManager?.beginUndoGrouping()
        defer {
            undoManager?.setActionName(String(localized: "Make Folder", comment: "Undo menu action name for showing selected Layout items as a folder"))
            undoManager?.endUndoGrouping()
        }
        if let existing = selectedGroup {
            LayoutEditUndo.setFolder(true, for: existing.origin, members: members(of: existing), name: name(of: existing), folders: folders, undoManager: undoManager)
            return
        }
        guard let created = group() else { return }
        let members = groupable
        LayoutEditUndo.setFolder(true, for: .user(created.id), members: members, name: folders.folderName(for: created), folders: folders, undoManager: undoManager)
    }

    /// Whether the selection's group already shows as a folder.
    func isFolder(_ folders: GroupFolders) -> Bool {
        selectedGroup.map { folders.isFolder($0.origin) } ?? false
    }

    /// What the menus and editor say when the selection can't be grouped.
    static func explanation(for refusal: Refusal) -> String {
        switch refusal {
        case .severalSections:
            String(localized: "Select items in one section to group them", comment: "Shown when the Layout selection spans sections")
        case .tooFewGroupable:
            String(localized: "Select two items that can be grouped", comment: "Shown when fewer than two selected Layout items can be grouped")
        }
    }
}
