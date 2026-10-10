//
//  UnresolvedSlotEditorDragTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Covers how the layout editor treats an unresolved Control Center slot
/// (`com.apple.controlcenter:Item-N` with no source PID).
///
/// In #1190 always-hidden held only such a slot, parked near x=-8454. Drops
/// anchored beside it landed off-screen and reverted, and dragging the slot
/// itself timed out after 8 attempts.
@Suite("Unresolved Control Center slot in the layout editor (#1190)")
struct UnresolvedSlotEditorDragTests {
    private static let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

    private static func slot(atX x: CGFloat) -> MenuBarItem {
        .fixture(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "Item-6"),
            windowID: 600,
            bounds: CGRect(x: x, y: 0, width: 24, height: 22),
            sourcePID: nil
        )
    }

    private static func app(_ bundleID: String, windowID: CGWindowID) -> MenuBarItem {
        .fixture(tag: .appItem(bundleID: bundleID, title: "Item-0"), windowID: windowID)
    }

    @Test("A slot parked off every display is not draggable")
    func parkedSlotIsNotDraggable() {
        #expect(!Self.slot(atX: -8454).isDraggableInLayoutEditor(displayBounds: [Self.display]))
    }

    @Test("A slot on a display keeps the Control Center move path")
    func onscreenSlotIsDraggable() {
        #expect(Self.slot(atX: 900).isDraggableInLayoutEditor(displayBounds: [Self.display]))
    }

    @Test("A resolved app item is draggable wherever it sits")
    func appItemIsDraggable() {
        let parkedApp = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.lwouis.alt-tab-macos", title: "Item-0"),
            windowID: 700,
            bounds: CGRect(x: -8454, y: 0, width: 24, height: 22)
        )
        #expect(parkedApp.isDraggableInLayoutEditor(displayBounds: [Self.display]))
    }

    @Test("A system item macOS prohibits stays undraggable")
    func prohibitedItemIsNotDraggable() {
        let clock = MenuBarItem.fixture(tag: .clock, windowID: 800)
        #expect(!clock.isDraggableInLayoutEditor(displayBounds: [Self.display]))
    }

    @Test("A drop skips the slot and anchors on the next real item")
    func dropSkipsSlot() {
        let altTab = Self.app("com.lwouis.alt-tab-macos", windowID: 1)
        let dropbox = Self.app("com.getdropbox.dropbox", windowID: 2)
        let slots: [MenuBarItem?] = [dropbox, Self.slot(atX: -8454), nil, altTab]

        let right = LayoutBarPaddingView.nearestDropAnchor(in: slots, from: 0, towardRight: true)
        #expect(right?.windowID == altTab.windowID)

        let left = LayoutBarPaddingView.nearestDropAnchor(in: slots, from: 3, towardRight: false)
        #expect(left?.windowID == dropbox.windowID)
    }

    @Test("A section holding only the slot has no item anchor")
    func onlySlotLeavesNoAnchor() {
        let dragged = Self.app("com.lwouis.alt-tab-macos", windowID: 1)
        let slots: [MenuBarItem?] = [Self.slot(atX: -8454), dragged]

        #expect(LayoutBarPaddingView.nearestDropAnchor(in: slots, from: 1, towardRight: false) == nil)
        #expect(LayoutBarPaddingView.nearestDropAnchor(in: slots, from: 1, towardRight: true) == nil)
    }
}
