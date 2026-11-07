//
//  MenuBarSearchPanel+Keyboard.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import ThawUI

extension MenuBarSearchPanel {
    /// The panel's key monitor: list moves, then the Command shortcuts.
    /// Returns nil for a key it handled.
    func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if handleListMove(event) {
            return nil
        }
        return handleCommandShortcut(event)
    }

    /// Moves the highlight for the arrows, Page Up, Page Down, Home and End,
    /// repeats included. Only for this panel's own key events, so the
    /// global half of the monitor cannot move it twice.
    private func handleListMove(_ event: NSEvent) -> Bool {
        guard
            event.window === self,
            model.renameSession == nil,
            let move = SearchListMove(
                key: KeyCode(rawValue: Int(event.keyCode)),
                modifiers: Modifiers(nsEventFlags: event.modifierFlags)
            )
        else {
            return false
        }
        model.moveSelection(move)
        return true
    }

    /// ⌘, opens Settings, ⌘E renames, ⌘K opens the actions menu, ⌘1 to ⌘3
    /// move the item between sections, ⌘L opens its layout pane.
    private func handleCommandShortcut(_ event: NSEvent) -> NSEvent? {
        guard Modifiers(nsEventFlags: event.modifierFlags) == .command else {
            return event
        }
        let keyCode = KeyCode(rawValue: Int(event.keyCode))
        if keyCode == .comma {
            close()
            appState?.activate(withPolicy: .regular)
            appState?.openWindow(.settings)
            return nil
        }
        if keyCode == .e {
            beginRenamingSelection()
            return nil
        }
        // With no highlighted row these keys pass through.
        guard
            model.renameSession == nil,
            let appState,
            selectedItem != nil
        else {
            return event
        }
        if keyCode == .k {
            presentItemActions()
            return nil
        }
        if keyCode == .l {
            close()
            MenuBarSearchItemActions.openSettings(appState: appState)
            return nil
        }
        if let index = [KeyCode.one, .two, .three].firstIndex(of: keyCode) {
            moveSelection(toDestinationAt: index)
            return nil
        }
        return event
    }

    /// Refocusing a text field selects all its text, so the next keystroke
    /// would replace the query. When placesQueryCaretAtEnd is set, the
    /// insertion point goes to the end instead. Matched on the outer call,
    /// whose target is the field: the inner one, for the field editor, comes
    /// before the field selects its text.
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let accepted = super.makeFirstResponder(responder)
        if accepted, placesQueryCaretAtEnd, responder is NSTextField,
           let editor = firstResponder as? NSTextView, editor.isFieldEditor
        {
            placesQueryCaretAtEnd = false
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        }
        return accepted
    }
}
