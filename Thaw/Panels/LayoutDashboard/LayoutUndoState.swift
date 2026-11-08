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
        let names: [Notification.Name] = [
            .NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange,
            .NSUndoManagerDidRedoChange, .NSUndoManagerCheckpoint,
        ]
        for name in names {
            NotificationCenter.default.publisher(for: name, object: undoManager)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refresh() }
                .store(in: &cancellables)
        }
        refresh()
    }

    func refresh() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
        undoTitle = undoManager.undoMenuItemTitle
        redoTitle = undoManager.redoMenuItemTitle
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
