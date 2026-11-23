//
//  HIDEventManagerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import Testing
@testable import Thaw
import ThawAXCore

/// A click over an icon the bar draws is not empty space, even when the walk
/// could not read the app that owns it.
@Suite("Drawn bar hit test")
struct DrawnBarHitTests {
    private let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let entries = [
        MenuBarAgentWindow.Entry(ownerPID: 500, frame: CGRect(x: 1300, y: 3, width: 24, height: 24)),
        MenuBarAgentWindow.Entry(ownerPID: 42, frame: CGRect(x: 1400, y: 3, width: 35, height: 24)),
    ]

    private func contains(_ point: CGPoint, laneMinX: CGFloat? = nil) -> Bool {
        HIDEventManager.drawnBarContains(
            point, entries: entries, ownPID: 42, destinationDisplay: display, displayBounds: [display], laneMinX: laneMinX
        )
    }

    @Test("A click counts over another app's drawn icon on the bar, not between icons, on Thaw's own or in the overflow", arguments: [
        (CGPoint(x: 1310, y: 15), nil, true),
        (CGPoint(x: 1310, y: 1), nil, true),
        (CGPoint(x: 1350, y: 15), nil, false),
        (CGPoint(x: 1410, y: 15), nil, false),
        (CGPoint(x: 1310, y: 15), 1350, false),
    ] as [(CGPoint, CGFloat?, Bool)])
    func clickOverDrawnIcon(point: CGPoint, laneMinX: CGFloat?, isOverItem: Bool) {
        #expect(contains(point, laneMinX: laneMinX) == isOverItem)
    }

    @Test("A frame too wide to be an item does not swallow the bar")
    func oversizedFrame() {
        let wide = [MenuBarAgentWindow.Entry(ownerPID: 500, frame: CGRect(x: 0, y: 0, width: 1920, height: 30))]
        #expect(!HIDEventManager.drawnBarContains(
            CGPoint(x: 900, y: 15), entries: wide, ownPID: 42, destinationDisplay: display, displayBounds: [display], laneMinX: nil
        ))
    }
}

/// Whether the pointer counts as on the Thaw Bar, which keeps revealed items from hiding.
@Suite("Thaw Bar pointer")
struct ThawBarPointerTests {
    private static let frame = CGRect(x: 800, y: 900, width: 300, height: 40)

    @Test("The pointer over an open bar, or just off its edge, is on it")
    func openBar() {
        #expect(HIDEventManager.isPointer(CGPoint(x: 900, y: 920), overThawBarAt: Self.frame, isVisible: true))
        #expect(HIDEventManager.isPointer(CGPoint(x: 790, y: 920), overThawBarAt: Self.frame, isVisible: true))
        #expect(!HIDEventManager.isPointer(CGPoint(x: 700, y: 920), overThawBarAt: Self.frame, isVisible: true))
    }

    @Test("A closed bar's last frame doesn't count, so items revealed inline can hide")
    func closedBar() {
        #expect(!HIDEventManager.isPointer(CGPoint(x: 900, y: 920), overThawBarAt: Self.frame, isVisible: false))
    }

    @Test("No pointer location is never on the bar")
    func noPointer() {
        #expect(!HIDEventManager.isPointer(nil, overThawBarAt: Self.frame, isVisible: true))
    }
}

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

@MainActor
@Suite("Smart rehide outside clicks")
struct SmartRehideClickTests {
    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 10, height: 10), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    /// A global mouse monitor hands over events for other apps' windows with no window, which is
    /// what an outside click looks like. The control item has no window until the system seats
    /// its status item, so it must not claim such a click.
    @Test("A click with no window is not a click on a control item that has no window either")
    func windowlessClickIsNotOnWindowlessControlItem() {
        #expect(!HIDEventManager.isClick(in: nil, onControlItemWindow: nil))
    }

    @Test("A click in the control item's window is a click on it")
    func clickInControlItemWindow() {
        let window = makeWindow()
        #expect(HIDEventManager.isClick(in: window, onControlItemWindow: window))
    }

    @Test("A click in another window, or a windowless control item, is not a click on it")
    func clickElsewhere() {
        let window = makeWindow()
        #expect(!HIDEventManager.isClick(in: window, onControlItemWindow: makeWindow()))
        #expect(!HIDEventManager.isClick(in: window, onControlItemWindow: nil))
        #expect(!HIDEventManager.isClick(in: nil, onControlItemWindow: window))
    }
}
