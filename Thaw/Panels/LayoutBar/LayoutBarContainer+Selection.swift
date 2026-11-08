//
//  LayoutBarContainer+Selection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import ThawUI

/// The bar's side of the pane's selection: what it can select, and the moves it starts.
extension LayoutBarContainer {
    /// The pane's selection, held by the scroll view around this bar.
    var selection: LayoutSelectionModel? {
        (enclosingScrollView as? LayoutBarScrollView)?.selection
    }

    /// The section's units left to right. A group the bar draws as one block is one unit.
    func selectionUnits() -> [LayoutSelection.Unit] {
        let itemViews = arrangedViews.compactMap { $0 as? LayoutBarItemView }
        let viewsByID = Dictionary(itemViews.map { ($0.item.uniqueIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        // Views that stand for no item keep their place so group indices still line up, then drop out.
        let itemIDs = arrangedViews.map { ($0 as? LayoutBarItemView)?.item.uniqueIdentifier ?? "" }
        let groups = resolvedGroups().map { (id: $0.origin.description, memberIndices: $0.memberIndices) }
        return LayoutEditorOrder.units(itemIDs: itemIDs, groups: groups)
            .filter { !$0.memberIDs.contains("") }
            .map { unit in
                LayoutSelection.Unit(
                    memberIDs: unit.memberIDs,
                    isSelectable: unit.memberIDs.allSatisfy { viewsByID[$0].map(Self.isSelectable) ?? false }
                )
            }
    }

    /// Thaw's own control items stay put, and so does anything the bar will not let a drag pick up.
    private static func isSelectable(_ view: LayoutBarItemView) -> Bool {
        view.isEnabled && !view.item.isControlItem
    }

    /// A rebuild adds and removes item views, so the selection rereads the bar once it settles.
    func scheduleSelectionSync() {
        guard selection != nil else { return }
        Task { @MainActor [weak self] in
            self?.syncSelection()
        }
    }

    /// Tells the selection what the bar shows now. Skipped mid-drag, when the bar shows a preview.
    func syncSelection() {
        guard acceptsViewUpdates else { return }
        selection?.update(selectionUnits(), in: section)
    }

    /// Applies a click on view to the selection.
    func applyClick(_ kind: LayoutSelection.Click, on view: LayoutBarItemView) {
        syncSelection()
        selection?.click(view.item.uniqueIdentifier, in: section, kind: kind)
    }

    /// Whether view is one of several selected items.
    func isPartOfSelection(_ view: LayoutBarItemView) -> Bool {
        guard let selection else { return false }
        return selection.count > 1 && selection.contains(view.item.uniqueIdentifier)
    }

    /// The menu for a right click on one of several selected items, or nil to show the item's own menu.
    func selectionMenu(for view: LayoutBarItemView) -> NSMenu? {
        guard isPartOfSelection(view) else { return nil }
        return selectionActions?.menu()
    }

    /// One move of the whole selection per section it can go to, when view is one of several selected items.
    func selectionMoves(for view: LayoutBarItemView) -> [(title: String, perform: @MainActor () -> Void)] {
        guard isPartOfSelection(view), let actions = selectionActions else { return [] }
        let count = actions.selection.count
        return actions.moveTargets().map { target in
            let title = String(
                localized: "Move \(count) Items to \(target.localizedName)",
                comment: "Menu entry that moves every selected Layout item to a section"
            )
            return (title, { actions.move(to: target, placement: .end) })
        }
    }

    /// The bars' share of the selection's moves, nil without a selection or app state.
    private var selectionActions: LayoutSelectionActions? {
        guard let selection, let appState else { return nil }
        return LayoutSelectionActions(selection: selection, appState: appState)
    }

    /// Whether this section would take the whole selection.
    func acceptsSelection() -> Bool {
        guard let appState, let selection else { return false }
        return selection.accepts(section, in: LayoutBatchMoveExecutor.snapshot(appState: appState))
    }

    /// Moves the selection to where a drop at windowLocation lands, the same slot the drop marker shows.
    func dropSelection(at windowLocation: NSPoint) {
        guard let selection else { return }
        let destination = groupDropDestination(atX: convert(windowLocation, from: nil).x)
        let order = LayoutBarPaddingView.layoutItemsForPersistence(from: arrangedViews).map(\.uniqueIdentifier)
        let placement = LayoutSelection.placement(
            insertingAt: destination.itemIndex,
            in: order,
            selected: Set(selection.orderedItemIDs)
        )
        moveSelection(to: section, placement: placement)
    }

    /// Moves the selection through LayoutSelectionActions, the path the Layout window's list uses too.
    private func moveSelection(to target: MenuBarSection.Name, placement: LayoutBatchMove.Placement) {
        selectionActions?.move(to: target, placement: placement)
    }
}

/// How an item shows and reports that it is selected.
extension LayoutBarItemView {
    /// Whether the item is part of the Layout pane's selection.
    var isLayoutSelected: Bool {
        (superview as? LayoutBarContainer)?.selection?.contains(item.uniqueIdentifier) ?? false
    }

    /// The section, and whether the item is selected, read live so VoiceOver never hears a stale state.
    func selectionAccessibilityValue() -> Any? {
        guard let section = (superview as? LayoutBarContainer)?.section else { return nil }
        return LayoutSelectionHighlight.accessibilityValue(section: section, isSelected: isLayoutSelected)
    }

    /// The item's own actions, then selecting it and, once several are selected, moving them all.
    func selectionAccessibilityActions(appendedTo own: [NSAccessibilityCustomAction]) -> [NSAccessibilityCustomAction] {
        guard let container = superview as? LayoutBarContainer, container.selection != nil,
              container.selectionUnits().contains(where: { $0.isSelectable && $0.memberIDs.contains(item.uniqueIdentifier) })
        else {
            return own
        }
        let toggleName = isLayoutSelected
            ? String(localized: "Deselect", comment: "VoiceOver action that removes a Layout item from the selection")
            : String(localized: "Add to Selection", comment: "VoiceOver action that adds a Layout item to the selection")
        let toggle = NSAccessibilityCustomAction(name: toggleName) { [weak self, weak container] in
            guard let self, let container else { return false }
            container.applyClick(.toggle, on: self)
            return true
        }
        let moves = container.selectionMoves(for: self).map { move in
            NSAccessibilityCustomAction(name: move.title) {
                move.perform()
                return true
            }
        }
        return own + [toggle] + moves
    }
}
