//
//  DragRevealSectionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("A ⌘-drag opens the deepest section there is")
struct DragRevealSectionTests {
    @Test func opensAlwaysHiddenWhenItIsEnabled() {
        #expect(HIDEventManager.sectionRevealedForDrag(enabled: [.visible, .hidden, .alwaysHidden]) == .alwaysHidden)
    }

    @Test func opensHiddenWhenAlwaysHiddenIsOff() {
        #expect(HIDEventManager.sectionRevealedForDrag(enabled: [.visible, .hidden]) == .hidden)
    }

    @Test func opensNothingWhenOnlyVisibleExists() {
        #expect(HIDEventManager.sectionRevealedForDrag(enabled: [.visible]) == nil)
    }
}

@Suite("A ⌘-drag opens sections only for an item that can go into one", .scratchDefaults)
struct DragRevealDecisionTests {
    private let appItem = MenuBarItemTag(namespace: .string("com.example.app"), title: "Item-0")

    @Test func opensForAnAppItem() {
        #expect(HIDEventManager.dragRevealsSections(enabled: true, nativeHidingActive: false, draggedTag: appItem))
    }

    /// macOS places the recording indicator itself, and the reveal redrew the
    /// whole bar under the drag.
    @Test func staysShutForTheRecordingIndicator() {
        #expect(!HIDEventManager.dragRevealsSections(
            enabled: true, nativeHidingActive: false, draggedTag: .screenCaptureUI
        ))
    }

    /// The cache leaves the indicators out, so a drag of one finds no item.
    @Test func staysShutWhenTheItemIsNotCached() {
        #expect(!HIDEventManager.dragRevealsSections(enabled: true, nativeHidingActive: false, draggedTag: nil))
    }

    @Test func staysShutForTheCameraIndicator() {
        #expect(!HIDEventManager.dragRevealsSections(
            enabled: true, nativeHidingActive: false, draggedTag: .audioVideoModule
        ))
    }

    /// Native hiding reveals by switching apps back on in macOS's own list,
    /// which rebuilds the bar while the drag is still moving.
    @Test func staysShutWithNativeHiding() {
        #expect(!HIDEventManager.dragRevealsSections(enabled: true, nativeHidingActive: true, draggedTag: appItem))
    }

    @Test func staysShutWhenTurnedOff() {
        #expect(!HIDEventManager.dragRevealsSections(enabled: false, nativeHidingActive: false, draggedTag: appItem))
    }

    @MainActor
    @Test func findsNoItemWithoutAPointer() {
        let appState = AppState()
        #expect(appState.hidEventManager.managedItem(appState: appState, at: nil) == nil)
    }

    @MainActor
    @Test func findsNoItemWhereNothingIsCached() {
        let appState = AppState()
        #expect(appState.hidEventManager.managedItem(appState: appState, at: CGPoint(x: 10, y: 5)) == nil)
    }

    /// A press without ⌘ is not the start of a move, so it forgets any item
    /// an earlier press grabbed.
    @MainActor
    @Test func aPlainPressForgetsTheGrabbedItem() throws {
        let appState = AppState()
        let manager = appState.hidEventManager
        manager.pressedItemTag = .screenCaptureUI
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        manager.notePressForItemDrag(event, appState: appState)
        #expect(manager.pressedItemTag == nil)
    }

    /// With nothing cached under the pointer, a ⌘-press grabs no item.
    @MainActor
    @Test func aCommandPressOverNothingGrabsNothing() throws {
        let appState = AppState()
        let manager = appState.hidEventManager
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        manager.notePressForItemDrag(event, appState: appState)
        #expect(manager.pressedItemTag == nil)
    }

    /// A ⌘-click that never became a drag must not leave its item behind for
    /// the next drag.
    @MainActor
    @Test func aReleaseWithoutADragForgetsTheGrabbedItem() {
        let appState = AppState()
        let manager = appState.hidEventManager
        manager.pressedItemTag = .screenCaptureUI
        manager.handleMenuBarItemDragStop()
        #expect(manager.pressedItemTag == nil)
    }
}
