//
//  LayoutBatchMoveUndo.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Undo for a multi-selection move: each item goes back after its old left neighbour. The redo is
/// registered before the async moves run, so it lands as a redo, not a new edit.
@MainActor
enum LayoutBatchMoveUndo {
    static func register(forward: LayoutBatchMove, restoring: [LayoutBatchMove], appState: AppState) {
        guard !restoring.isEmpty else { return }
        appState.layoutUndo.registerUndo(withTarget: appState) { appState in
            registerRedo(forward: forward, restoring: restoring, appState: appState)
            run(restoring, appState: appState)
        }
        appState.layoutUndo.setActionName(actionName(count: forward.itemIDs.count))
    }

    private static func registerRedo(forward: LayoutBatchMove, restoring: [LayoutBatchMove], appState: AppState) {
        appState.layoutUndo.registerUndo(withTarget: appState) { appState in
            register(forward: forward, restoring: restoring, appState: appState)
            run([forward], appState: appState)
        }
        appState.layoutUndo.setActionName(actionName(count: forward.itemIDs.count))
    }

    private static func run(_ moves: [LayoutBatchMove], appState: AppState) {
        ExplicitLayoutEdit.task {
            for move in moves {
                _ = await LayoutBatchMoveExecutor(appState: appState).run(move)
            }
        }
    }

    /// Only a move that happened gets an undo step; a refused or unchanged one leaves none.
    static nonisolated func records(_ outcome: LayoutBatchMoveOutcome?) -> Bool {
        if case .moved = outcome {
            true
        } else {
            false
        }
    }

    static nonisolated func actionName(count: Int) -> String {
        String(localized: "Move \(count) Items", comment: "Undo menu action name for moving several selected menu bar items")
    }
}
