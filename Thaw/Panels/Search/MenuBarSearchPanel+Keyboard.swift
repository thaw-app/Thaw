//
//  MenuBarSearchPanel+Keyboard.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import ThawUI

extension MenuBarSearchPanel {
    /// Whether a result row shows. Compact collapsed to its field shows none, so keys that act on the
    /// highlighted row pass through.
    var showsAResultRow: Bool {
        !(presentation.isCollapsed(query: model.searchText) && model.renameSession == nil)
    }

    /// Whether an input method, such as Japanese or Chinese, is composing in the field. Its composition
    /// owns Return, the arrows and Escape, so every key passes through until it ends.
    var isComposingText: Bool {
        (firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }

    /// The one place the panel's keys are read, as in Floe: a second handler
    /// wrote a stale highlight back on held-arrow repeats. Nil when handled.
    func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard !isComposingText else { return event }
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
            event.window === self, model.renameSession == nil, showsAResultRow, key == .returnKey || key == .keypadEnter, Modifiers(nsEventFlags: event.modifierFlags).isEmpty, let item = model.selectedResult?.item
        else {
            return false
        }
        activate(item)
        return true
    }

    /// Tab moves the highlight to the next section, Shift-Tab to the previous
    /// one. With no second section to jump to, Tab passes through and moves
    /// the keyboard focus, so the panel's buttons stay reachable.
    private func handleSectionJump(_ event: NSEvent) -> Bool {
        let modifiers = Modifiers(nsEventFlags: event.modifierFlags)
        guard
            event.window === self, model.renameSession == nil, KeyCode(rawValue: Int(event.keyCode)) == .tab, modifiers.isEmpty || modifiers == .shift, showsAResultRow, model.canJumpBetweenSections
        else {
            return false
        }
        model.moveSelection(toSectionFromCurrentBy: modifiers == .shift ? -1 : 1)
        announceSelection()
        return true
    }

    /// Arrows, Page Up, Page Down, Home and End, repeats included. Only the
    /// panel's own events, so the global monitor can't move it twice. With no
    /// row showing they pass through and move the field's text cursor instead.
    private func handleListMove(_ event: NSEvent) -> Bool {
        guard
            event.window === self, model.renameSession == nil, showsAResultRow, Modifiers(nsEventFlags: event.modifierFlags).isEmpty, let delta = LauncherListStep.delta(for: KeyCode(rawValue: Int(event.keyCode)))
        else {
            return false
        }
        model.moveSelection(by: delta)
        announceSelection()
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
            appState?.activate(withPolicy: appState?.userWindowActivationPolicy)
            appState?.openWindow(.settings)
            return nil
        }
        // With the panel collapsed to its field, no row shows to act on.
        guard showsAResultRow else {
            return event
        }
        if keyCode == .e, model.renameSession == nil {
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

    /// Refocusing a field selects its text, so typing would replace the query.
    /// Matched on the outer call: the inner one comes before the selection.
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let accepted = super.makeFirstResponder(responder)
        if accepted, placesQueryCaretAtEnd, responder is NSTextField, let editor = firstResponder as? NSTextView, editor.isFieldEditor {
            placesQueryCaretAtEnd = false
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        }
        return accepted
    }
}
