//
//  LayoutUndoShortcuts.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import SwiftUI

/// ⌘Z and ⇧⌘Z for the layout history wherever the keyboard is in the pane.
/// Settings has no Edit menu, so without these undo needed a focused tile.
struct LayoutUndoShortcuts: ViewModifier {
    let undoManager: UndoManager

    func body(content: Content) -> some View {
        content.background {
            Group {
                Button("Undo") { undoManager.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Redo") { undoManager.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            .hidden()
            .accessibilityHidden(true)
        }
    }
}
