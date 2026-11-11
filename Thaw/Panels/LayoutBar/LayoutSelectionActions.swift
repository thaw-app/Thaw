//
//  LayoutSelectionActions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Algorithms
import AppKit
import MenuBarModel
import ThawUI

/// What can be done with several selected Layout items, from the bars or the Layout window's list:
/// one path for the moves, their refusals and their undo.
@MainActor
struct LayoutSelectionActions {
    let selection: LayoutSelectionModel
    let appState: AppState

    /// The sections the whole selection can move to.
    func moveTargets() -> [MenuBarSectionName] {
        selection.moveTargets(in: LayoutBatchMoveExecutor.snapshot(appState: appState))
    }

    /// The menu for several selected items: a count, then a move per section that takes them all.
    func menu() -> NSMenu? {
        guard selection.count > 1 else { return nil }
        let count = selection.count
        let menu = NSMenu()
        let header = NSMenuItem(
            title: String(localized: "\(count) Items Selected", comment: "Header of the menu for several selected Layout items"),
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        for target in moveTargets() {
            let title = String(
                localized: "Move \(count) Items to \(target.localizedName)",
                comment: "Menu entry that moves every selected Layout item to a section"
            )
            menu.addItem(ClosureMenuItem(title: title) { move(to: target, placement: .end) })
        }
        if let grouping = LayoutSelectionGrouping.make(selection: selection, appState: appState) {
            menu.addItem(.separator())
            addGroupingEntries(to: menu, grouping: grouping)
        }
        menu.addItem(.separator())
        menu.addItem(alertRevealEntry())
        return menu
    }

    /// Group Selected, Add to Group and Make Folder, or one line saying why grouping isn't offered.
    func addGroupingEntries(to menu: NSMenu, grouping: LayoutSelectionGrouping) {
        if let refusal = grouping.refusal {
            menu.addItem(ClosureMenuItem(title: LayoutSelectionGrouping.explanation(for: refusal), isEnabled: false) {
                // A note, not a command: the item is disabled and never runs this.
            })
            return
        }
        let groupEntry = ClosureMenuItem(
            title: String(localized: "Group \(grouping.items.count) Items", comment: "Menu entry that makes one group of the selected Layout items")
        ) { grouping.group() }
        groupEntry.isEnabled = grouping.canGroup
        menu.addItem(groupEntry)

        let joinable = grouping.joinableGroups
        if !joinable.isEmpty {
            let submenu = NSMenu()
            for group in joinable {
                submenu.addItem(ClosureMenuItem(title: grouping.name(of: group)) { grouping.add(to: group) })
            }
            let entry = NSMenuItem(title: String(localized: "Add to Group"), action: nil, keyEquivalent: "")
            entry.submenu = submenu
            menu.addItem(entry)
        }

        let folders = appState.groupFolders
        let folderEntry = ClosureMenuItem(title: String(localized: "Make Folder", comment: "Menu entry that shows the selected Layout items as a folder")) {
            grouping.makeFolder(folders: folders)
        }
        let isFolder = grouping.isFolder(folders)
        folderEntry.state = isFolder ? .on : .off
        folderEntry.isEnabled = !isFolder
        menu.addItem(folderEntry)
    }

    /// The single-item menu's Show When Its Icon Changes, for every selected item at once.
    private func alertRevealEntry() -> NSMenuItem {
        let identifiers = LayoutSelectionActions.alertRevealIdentifiers(selection.orderedItemIDs, items: appState.itemManager.managedItems)
        let isEnabled = !identifiers.isEmpty && identifiers.allSatisfy(MenuBarItemAlertReveals.contains)
        let entry = ClosureMenuItem(
            title: String(localized: "Show When Their Icons Change", comment: "Menu entry that reveals every selected Layout item when its icon changes")
        ) {
            for identifier in identifiers {
                MenuBarItemAlertReveals.setEnabled(!isEnabled, for: identifier)
            }
        }
        entry.state = isEnabled ? .on : .off
        entry.isEnabled = !identifiers.isEmpty
        return entry
    }

    /// The alert-reveal identifiers of the selected items, skipping Thaw's own.
    static func alertRevealIdentifiers(_ itemIDs: [String], items: [MenuBarItem]) -> [String] {
        let selected = Set(itemIDs)
        return Array(
            items.filter { selected.contains($0.uniqueIdentifier) && !$0.isControlItem }
                .map(\.tag.tagIdentifier)
                .uniqued()
        )
    }

    /// One batch through the move path thaw://move-item uses, counted as a user edit and undoable.
    /// A move that lands is spoken to VoiceOver; keepsSelection selects the moved items again once their bar shows them,
    /// and puts the selection back when the move was refused or changed nothing.
    /// onMoved gets the moved items only when the move lands.
    func move(
        to target: MenuBarSectionName,
        placement: LayoutBatchMove.Placement,
        keepsSelection: Bool = false,
        onMoved: @escaping @MainActor ([String]) -> Void = { _ in /* Nothing more to do by default. */ }
    ) {
        let restoring = selection.restoringMoves()
        let previousSelection = selection.selection
        let forward = selection.command(to: target, placement: placement)
        let selection = selection
        let appState = appState
        ExplicitLayoutEdit.task {
            let outcome = await selection.move(to: target, placement: placement, using: selection.makeMover(appState))
            if LayoutBatchMoveUndo.records(outcome), let forward {
                LayoutBatchMoveUndo.register(forward: forward, restoring: restoring, appState: appState)
            }
            if case .moved = outcome, let forward {
                AccessibilityAnnouncements.post(LayoutSelectionModel.movedAnnouncement(count: forward.itemIDs.count, to: target))
                if keepsSelection {
                    selection.reselect(forward.itemIDs, in: target)
                }
                onMoved(forward.itemIDs)
            }
            if keepsSelection, LayoutSelectionModel.leftItemsInPlace(outcome) {
                selection.restore(previousSelection)
            }
            guard let outcome, let refusal = LayoutSelectionModel.refusal(for: outcome, section: target, itemName: { id in
                appState.itemManager.managedItems.first { $0.uniqueIdentifier == id }?.displayName
            })
            else {
                return
            }
            appState.layoutFeedback.post(refusal)
        }
    }
}
