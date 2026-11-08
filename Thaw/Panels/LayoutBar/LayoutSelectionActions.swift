//
//  LayoutSelectionActions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

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
        return menu
    }

    /// One batch through the move path thaw://move-item uses, counted as a user edit and undoable.
    func move(to target: MenuBarSectionName, placement: LayoutBatchMove.Placement) {
        let restoring = selection.restoringMoves()
        let forward = selection.command(to: target, placement: placement)
        let selection = selection
        let appState = appState
        ExplicitLayoutEdit.task {
            let outcome = await selection.move(to: target, placement: placement, using: selection.makeMover(appState))
            if LayoutBatchMoveUndo.records(outcome), let forward {
                LayoutBatchMoveUndo.register(forward: forward, restoring: restoring, appState: appState)
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
