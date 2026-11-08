//
//  LayoutUndoState.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import Observation

/// What the layout history can undo and redo, for the Layout window's toolbar.
/// UndoManager isn't observable, so this follows its notifications.
@MainActor
@Observable
final class LayoutUndoState {
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var undoTitle = ""
    private(set) var redoTitle = ""

    @ObservationIgnored let undoManager: UndoManager
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    init(undoManager: UndoManager) {
        self.undoManager = undoManager
        // Not the checkpoint notification: reading canRedo posts it, so refreshing on it loops.
        let names: [Notification.Name] = [
            .NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange,
        ]
        for name in names {
            NotificationCenter.default.publisher(for: name, object: undoManager)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refresh() }
                .store(in: &cancellables)
        }
        refresh()
    }

    /// How many times the state was read from the history; tests use it to catch a feedback loop.
    @ObservationIgnored private(set) var refreshCount = 0

    func refresh() {
        refreshCount += 1
        // Unchanged values aren't written, so they don't redraw the toolbar.
        let (undo, redo) = (undoManager.canUndo, undoManager.canRedo)
        let (undoName, redoName) = (undoManager.undoMenuItemTitle, undoManager.redoMenuItemTitle)
        if canUndo != undo { canUndo = undo }
        if canRedo != redo { canRedo = redo }
        if undoTitle != undoName { undoTitle = undoName }
        if redoTitle != redoName { redoTitle = redoName }
    }

    func undo() {
        guard undoManager.canUndo else { return }
        undoManager.undo()
        refresh()
    }

    func redo() {
        guard undoManager.canRedo else { return }
        undoManager.redo()
        refresh()
    }
}
