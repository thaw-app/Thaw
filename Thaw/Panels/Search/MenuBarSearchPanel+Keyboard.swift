//
//  MenuBarSearchPanel+Keyboard.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import ThawUI

extension MenuBarSearchPanel {
    /// The panel's key monitor: list moves and Return, then the Command
    /// shortcuts. Returns nil for a key it handled. The one place the panel's
    /// row keys are read, as in Floe: a second handler on the query field
    /// wrote a stale highlight back after each held-arrow repeat.
    func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if handleListMove(event) || handleSectionJump(event) || handleReturn(event) {
            return nil
        }
        return handleCommandShortcut(event)
    }

    /// Return, or the keypad's Enter, opens the highlighted row. A rename
    /// keeps them, for its own field.
    private func handleReturn(_ event: NSEvent) -> Bool {
        let key = KeyCode(rawValue: Int(event.keyCode))
        guard
            event.window === self, model.renameSession == nil, key == .returnKey || key == .keypadEnter, Modifiers(nsEventFlags: event.modifierFlags).isEmpty, let item = model.selectedResult?.item
        else {
            return false
        }
        activate(item)
        return true
    }

    /// Tab moves the highlight to the next section, Shift-Tab to the previous
    /// one. Taken either way, so Tab never moves the keyboard out of the field.
    private func handleSectionJump(_ event: NSEvent) -> Bool {
        let modifiers = Modifiers(nsEventFlags: event.modifierFlags)
        guard
            event.window === self, model.renameSession == nil, KeyCode(rawValue: Int(event.keyCode)) == .tab, modifiers.isEmpty || modifiers == .shift
        else {
            return false
        }
        model.moveSelection(toSectionFromCurrentBy: modifiers == .shift ? -1 : 1)
        return true
    }

    /// Moves the highlight for the arrows, Page Up, Page Down, Home and End,
    /// repeats included. Only for this panel's own key events, so the
    /// global half of the monitor cannot move it twice. A key held with
    /// Shift, Option, Command or Control is the search field's.
    private func handleListMove(_ event: NSEvent) -> Bool {
        guard
            event.window === self, model.renameSession == nil, Modifiers(nsEventFlags: event.modifierFlags).isEmpty, let delta = LauncherListStep.delta(for: KeyCode(rawValue: Int(event.keyCode)))
        else {
            return false
        }
        model.moveSelection(by: delta)
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
            model.renameSession == nil, let appState, selectedItem != nil
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
        if accepted, placesQueryCaretAtEnd, responder is NSTextField, let editor = firstResponder as? NSTextView, editor.isFieldEditor {
            placesQueryCaretAtEnd = false
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        }
        return accepted
    }
}
