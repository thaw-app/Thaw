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
            let executor = LayoutBatchMoveExecutor(appState: appState)
            var outcomes = [LayoutBatchMoveOutcome]()
            for move in moves {
                await outcomes.append(run(move) { await executor.run($0) })
            }
            if let refusal = refusal(for: outcomes) {
                appState.layoutFeedback.post(refusal)
            }
        }
    }

    /// One step of an undo or redo. When the neighbour an item goes back after has quit or moved,
    /// the item goes to the end of its old section instead.
    static func run(
        _ move: LayoutBatchMove,
        using execute: (LayoutBatchMove) async -> LayoutBatchMoveOutcome
    ) async -> LayoutBatchMoveOutcome {
        let outcome = await execute(move)
        guard case .refused(.unknownAnchor) = outcome else { return outcome }
        return await execute(LayoutBatchMove(itemIDs: move.itemIDs, section: move.section, placement: .end))
    }

    /// What the pane says when part of an undo or redo was refused; nil when every step went through.
    static nonisolated func refusal(for outcomes: [LayoutBatchMoveOutcome]) -> LayoutBarFeedbackCenter.Refusal? {
        let wasRefused = outcomes.contains { outcome in
            if case .refused = outcome {
                true
            } else {
                false
            }
        }
        guard wasRefused else { return nil }
        return LayoutBarFeedbackCenter.Refusal(
            title: String(
                localized: "Some items couldn’t be moved back",
                comment: "Title shown when undoing or redoing a move of several Layout items was partly refused"
            ),
            message: String(
                localized: "An item has quit or changed since the move, so it stayed where it is.",
                comment: "Explanation shown when undoing or redoing a move of several Layout items was partly refused"
            )
        )
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
