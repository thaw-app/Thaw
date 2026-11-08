//
//  LayoutGroupNavigation.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI

/// The Layout window's Groups tab as a navigator: a group selects its members in the list and bars,
/// and items dropped on a group join it.
@MainActor
struct LayoutGroupNavigation {
    let selection: LayoutSelectionModel
    let appState: AppState

    /// Selects the group's members the bars show.
    func select(_ group: MenuBarItemGroup) {
        selection.select(group.memberIdentifiers)
    }

    /// Whether the selection is exactly the group's members the bars show.
    func isSelected(_ group: MenuBarItemGroup) -> Bool {
        let selected = Set(selection.orderedItemIDs)
        guard !selected.isEmpty else { return false }
        let members = Set(group.memberIdentifiers)
        return selected.isSubset(of: members) && selected.count == members.intersection(shownItemIDs).count
    }

    private var shownItemIDs: Set<String> {
        Set(MenuBarSectionName.allCases.flatMap { selection.units(in: $0).flatMap(\.memberIDs) })
    }

    /// Adds the items to group. Items from another section are refused, as the single-item menu
    /// only offers a section's own groups. Returns whether anything was added.
    @discardableResult
    func add(_ itemIDs: [String], to group: MenuBarItemGroup) -> Bool {
        let outcome = Self.add(
            itemIDs,
            to: group,
            manager: appState.itemGroupManager,
            undoManager: appState.layoutUndo,
            sectionItems: { section in
                let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
                return LayoutDisplayedItems.items(in: section, appState: appState, runningApplications: running)
            }
        )
        if case let .refused(section) = outcome {
            appState.layoutFeedback.post(LayoutBarFeedbackCenter.Refusal(
                title: String(
                    localized: "Only items in \(section.localizedName) can join “\(appState.groupFolders.folderName(for: group))”",
                    comment: "Title shown when items from another section are dropped on a Layout group"
                ),
                message: String(
                    localized: "Move the items to \(section.localizedName) first, then drop them on the group again.",
                    comment: "Explanation shown when items from another section are dropped on a Layout group"
                )
            ))
        }
        return outcome == .added
    }

    enum AddOutcome: Equatable {
        case added
        /// Nothing new to add: the items are members already, can't be grouped, or the group isn't shown.
        case unchanged
        /// Some items sit outside the group's section, named here.
        case refused(MenuBarSectionName)
    }

    /// The add, given each section's items left to right.
    static func add(
        _ itemIDs: [String],
        to group: MenuBarItemGroup,
        manager: MenuBarItemGroupManager,
        undoManager: UndoManager?,
        sectionItems: (MenuBarSectionName) -> [MenuBarItem]
    ) -> AddOutcome {
        let members = Set(group.memberIdentifiers)
        let layout = MenuBarSectionName.allCases.map { ($0, sectionItems($0)) }
        guard let (section, items) = layout.first(where: { $0.1.contains { members.contains($0.uniqueIdentifier) } }) else {
            return .unchanged
        }
        let dropped = Set(itemIDs)
        let outside = layout.contains { other in
            other.0 != section && other.1.contains { dropped.contains($0.uniqueIdentifier) }
        }
        if outside {
            return .refused(section)
        }
        let joining = items.filter { dropped.contains($0.uniqueIdentifier) }
        let grouping = LayoutSelectionGrouping(items: joining, sectionItems: items, manager: manager, undoManager: undoManager)
        guard let resolved = grouping.joinableGroups.first(where: { $0.origin == .user(group.id) }) else {
            return .unchanged
        }
        let before = manager.snapshot()
        grouping.add(to: resolved)
        return manager.snapshot() == before ? .unchanged : .added
    }
}

extension NSPasteboard.PasteboardType {
    /// The drags a Layout group takes: a bar glyph, the bars' selection, or rows from the list.
    static let layoutGroupDropTypes: [Self] = [.layoutBarItem, .layoutBarSelection]
}

/// Takes bar and list drags for one group row. It never ends the drag as a move, so the bars put
/// the dragged items back where they were, now members of the group.
struct LayoutGroupDropTarget: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let selection: LayoutSelectionModel
    let perform: @MainActor ([String]) -> Void

    func makeNSView(context _: Context) -> DropView {
        let view = DropView()
        view.registerForDraggedTypes(NSPasteboard.PasteboardType.layoutGroupDropTypes)
        update(view)
        return view
    }

    func updateNSView(_ view: DropView, context _: Context) {
        update(view)
    }

    private func update(_ view: DropView) {
        view.selection = selection
        view.perform = perform
        view.setTargeted = { isTargeted = $0 }
    }

    /// The item IDs a drag carries: the IDs written on the pasteboard, else the dragged glyph, else the selection.
    @MainActor
    static func itemIDs(pasteboard: NSPasteboard, source: Any?, selection: LayoutSelectionModel) -> [String] {
        if let written = pasteboard.string(forType: .layoutBarSelection), !written.isEmpty {
            return written.split(separator: "\n").map(String.init)
        }
        if let glyph = source as? LayoutBarItemView, !selection.contains(glyph.item.uniqueIdentifier) {
            return [glyph.item.uniqueIdentifier]
        }
        return selection.orderedItemIDs
    }

    final class DropView: NSView {
        var selection: LayoutSelectionModel?
        var perform: (@MainActor ([String]) -> Void)?
        var setTargeted: ((Bool) -> Void)?

        /// Clicks go to the row's controls; drags still find this view by its registered types.
        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }

        override func draggingEntered(_: NSDraggingInfo) -> NSDragOperation {
            setTargeted?(true)
            return .move
        }

        override func draggingUpdated(_: NSDraggingInfo) -> NSDragOperation {
            .move
        }

        override func draggingExited(_: NSDraggingInfo?) {
            setTargeted?(false)
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            setTargeted?(false)
            guard let selection else { return false }
            let ids = LayoutGroupDropTarget.itemIDs(pasteboard: sender.draggingPasteboard, source: sender.draggingSource, selection: selection)
            perform?(ids)
            // Not a move: the bars slide their items home and thaw, which they do only for a drag that didn't land.
            return false
        }
    }
}
