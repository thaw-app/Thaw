//
//  HoverDragHoldTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@Suite("Hover during a ⌘-drag")
struct HoverDragHoldTests {
    @Test("Hover waits while ⌘ is down or an item is being dragged")
    func heldDuringDrag() {
        #expect(HIDEventManager.holdsHoverChanges(modifierFlags: [.command], isDraggingMenuBarItem: false))
        #expect(HIDEventManager.holdsHoverChanges(modifierFlags: [.command, .shift], isDraggingMenuBarItem: false))
        #expect(HIDEventManager.holdsHoverChanges(modifierFlags: [], isDraggingMenuBarItem: true))
    }

    @Test("Other modifiers leave hover alone")
    func otherModifiers() {
        #expect(!HIDEventManager.holdsHoverChanges(modifierFlags: [], isDraggingMenuBarItem: false))
        #expect(!HIDEventManager.holdsHoverChanges(modifierFlags: [.option, .shift, .control], isDraggingMenuBarItem: false))
    }

    @Test("The existing hover gate still decides when hover runs at all")
    func existingGate() {
        #expect(HIDEventManager.shouldProcessHover(showOnHover: true, showOnHoverAllowed: true, sectionIsHidden: true))
        #expect(!HIDEventManager.shouldProcessHover(showOnHover: false, showOnHoverAllowed: true, sectionIsHidden: true))
        #expect(!HIDEventManager.shouldProcessHover(showOnHover: true, showOnHoverAllowed: false, sectionIsHidden: true))
        #expect(HIDEventManager.shouldProcessHover(showOnHover: true, showOnHoverAllowed: false, sectionIsHidden: false))
    }
}
