//
//  HIDEventManager+MenuBarItemDrag.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import AppKit
import Foundation
import MenuBarModel

extension HIDEventManager {
    // MARK: Handle Menu Bar Item Drag Stop

    /// Ends an item drag, and arranges for the cache to catch up with wherever
    /// the user dropped things.
    func handleMenuBarItemDragStop() {
        // Every release forgets the grabbed item, also when no drag started.
        pressedItemTag = nil
        guard isDraggingMenuBarItem else {
            return
        }
        isDraggingMenuBarItem = false

        guard let appState else {
            return
        }
        // Suppresses caching for 1 s and order restoration for 2 s, then
        // recaches to pick up the new positions.
        appState.itemManager.recordExternalMoveOperation()
        Task { [weak appState] in
            try? await Task.sleep(for: .milliseconds(500))
            await appState?.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
        }
    }

    // MARK: Handle Menu Bar Item Drag Start

    /// The item under a ⌘-press, read from the event's position, since the
    /// pointer may be over a neighbor by the time the drag starts.
    func notePressForItemDrag(_ event: NSEvent, appState: AppState) {
        pressedItemTag = event.modifierFlags.contains(.command)
            ? managedItem(appState: appState, at: event.cgEvent?.location ?? MouseHelpers.locationCoreGraphics)?.tag
            : nil
    }

    /// Notices the start of an item drag.
    ///
    /// Holding command is what makes a drag in the menu bar a move of the item
    /// rather than a drag inside whichever app owns it.
    func handleMenuBarItemDragStart(
        with event: NSEvent,
        appState: AppState,
        screen: NSScreen
    ) {
        guard
            !isDraggingMenuBarItem,
            event.modifierFlags.contains(.command),
            isMouseInsideMenuBarItem(appState: appState, screen: screen)
        else {
            return
        }

        isDraggingMenuBarItem = true
        appState.itemManager.repairs.interruptAutomaticWork(by: .userDragStarted)

        // Optionally bring every section out for the duration of the drag, so
        // the user can drop an item into one that is currently put away.
        guard Self.dragRevealsSections(
            enabled: configuration.showAllSectionsOnUserDrag,
            nativeHidingActive: appState.menuBarManager.nativeAppHidingExperiment.isActive,
            draggedTag: pressedItemTag
        ) else {
            return
        }
        // Reveal through the section itself, inline: redrawing the dividers
        // alone leaves the items put away and the dividers side by side.
        let enabled = Set(appState.menuBarManager.sections.filter(\.isEnabled).map(\.name))
        if let name = Self.sectionRevealedForDrag(enabled: enabled) {
            appState.menuBarManager.section(withName: name)?.show(forcingInline: true)
        }
        for section in appState.menuBarManager.sections {
            section.controlItem.state = .showSection
        }
    }

    /// Only hideable items the cache holds open the sections, so indicators and
    /// control items don't. With native hiding a reveal would rebuild the bar under the drag.
    static nonisolated func dragRevealsSections(
        enabled: Bool,
        nativeHidingActive: Bool,
        draggedTag: MenuBarItemTag?
    ) -> Bool {
        guard enabled, !nativeHidingActive, let draggedTag else { return false }
        return draggedTag.canBeHidden
    }

    /// The deepest section a drag opens, so every section is a drop target.
    static nonisolated func sectionRevealedForDrag(enabled: Set<MenuBarSection.Name>) -> MenuBarSection.Name? {
        [.alwaysHidden, .hidden].first(where: enabled.contains)
    }
}
