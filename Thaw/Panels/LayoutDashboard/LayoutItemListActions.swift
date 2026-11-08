//
//  LayoutItemListActions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import UniformTypeIdentifiers

/// The list's keyboard moves. Each is one batch through the bars' move path, so refusals and undo
/// match a drag, and the moved items stay selected so the next key works on them too.
@MainActor
struct LayoutItemListActions {
    let selection: LayoutSelectionModel
    let appState: AppState

    /// The section the whole selection is in, when it is in one.
    var selectedSection: MenuBarSectionName? {
        let sections = selection.selection.sections
        return sections.count == 1 ? sections.first : nil
    }

    func nudge(left: Bool) {
        guard let section = selectedSection, let entries = LayoutBatchMoveExecutor.snapshot(appState: appState).sections[section], let placement = LayoutItemListPlacement.nudge(selection.orderedItemIDs, in: entries, left: left)
        else {
            return
        }
        LayoutSelectionActions(selection: selection, appState: appState).move(to: section, placement: placement, keepsSelection: true)
    }

    func moveToAdjacentSection(up: Bool) {
        let destinations = MenuBarSearchItemActions.moveDestinations(appState: appState)
        guard let section = selectedSection, let target = LayoutItemListPlacement.adjacent(to: section, up: up, destinations: destinations)
        else {
            return
        }
        LayoutItemVisibility.moveSelection(to: target, selection: selection, appState: appState, keepsSelection: true)
    }

    func moveToSection(number: Int) {
        let destinations = MenuBarSearchItemActions.moveDestinations(appState: appState)
        guard !selection.orderedItemIDs.isEmpty, let target = LayoutItemListPlacement.numbered(number, destinations: destinations), target != selectedSection
        else {
            return
        }
        LayoutItemVisibility.moveSelection(to: target, selection: selection, appState: appState, keepsSelection: true)
    }
}

/// Rows dragged in the list. A drag carries the pasteboard type the bars' selection drags use, holding
/// the dragged items' identifiers one per line, or nothing to mean the shared selection, so the bars,
/// the list and the Groups tab read the same drag. On a heading the items join that section beside
/// its divider; on a row they land just left of it.
@MainActor
enum LayoutItemListDrop {
    static let type = UTType(importedAs: NSPasteboard.PasteboardType.layoutBarSelection.rawValue)

    /// What a drag of rowID carries: the selection when the row is in it, otherwise the row alone,
    /// which it selects so the bars show what is moving.
    static func provider(for rowID: String, in section: MenuBarSectionName, selection: LayoutSelectionModel) -> NSItemProvider {
        if !selection.contains(rowID) {
            selection.click(rowID, in: section, kind: .replace)
        }
        let payload = Data(selection.orderedItemIDs.joined(separator: "\n").utf8)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { completion in
            completion(payload, nil)
            return nil
        }
        return provider
    }

    /// Reads the dropped identifiers, then runs perform with them on the main actor.
    static func load(_ providers: [NSItemProvider], perform: @escaping @MainActor ([String]) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type.identifier) }) else {
            return false
        }
        _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let ids = text.split(separator: "\n").map(String.init)
            Task { @MainActor in perform(ids) }
        }
        return true
    }

    static func drop(_ ids: [String], before row: LayoutItemListRow, selection: LayoutSelectionModel, appState: AppState) {
        guard let moving = select(ids, in: selection) else { return }
        let order = LayoutBatchMoveExecutor.snapshot(appState: appState).sections[row.section]?.map(\.id) ?? []
        guard let placement = LayoutItemListPlacement.drop(Set(moving), before: row.id, in: order) else { return }
        LayoutSelectionActions(selection: selection, appState: appState).move(to: row.section, placement: placement, keepsSelection: true)
    }

    static func dropOnSection(_ ids: [String], section: MenuBarSectionName, selection: LayoutSelectionModel, appState: AppState) {
        guard select(ids, in: selection) != nil else { return }
        LayoutItemVisibility.moveSelection(to: section, selection: selection, appState: appState, keepsSelection: true)
    }

    /// Makes the dropped items the selection and returns them in bar order. No identifiers means the
    /// selection as it is. Nil when none of them is an item the bars list.
    static func select(_ ids: [String], in selection: LayoutSelectionModel) -> [String]? {
        if !ids.isEmpty, Set(ids) != Set(selection.orderedItemIDs) {
            var first = true
            for id in ids {
                guard let section = MenuBarSectionName.allCases.first(where: { section in
                    selection.units(in: section).contains { $0.memberIDs.contains(id) }
                }) else {
                    continue
                }
                if first {
                    selection.click(id, in: section, kind: .replace)
                    first = false
                } else if !selection.contains(id) {
                    selection.click(id, in: section, kind: .toggle)
                }
            }
            if first {
                return nil
            }
        }
        let moving = selection.orderedItemIDs
        return moving.isEmpty ? nil : moving
    }
}
