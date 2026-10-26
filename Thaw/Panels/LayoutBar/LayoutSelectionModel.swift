//
//  LayoutSelectionModel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// The Layout pane's selection, shared by every section's bar, and the move it hands to the batch path.
@MainActor
@Observable
final class LayoutSelectionModel {
    typealias Unit = LayoutSelection.Unit
    typealias Mover = @MainActor (LayoutBatchMove) async -> LayoutBatchMoveOutcome

    private(set) var selection = LayoutSelection()

    /// Each section's units as its bar last read them.
    @ObservationIgnored private var units = [MenuBarSectionName: [Unit]]()
    /// Makes the step that carries out a move; the live one is the path thaw://move-item uses.
    @ObservationIgnored var makeMover: (AppState) -> Mover = { appState in
        { await LayoutBatchMoveExecutor(appState: appState).run($0) }
    }

    /// Speaks a selection change to VoiceOver.
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    /// Runs each time a Command or Shift click grows the selection from fewer than two items to two or more.
    @ObservationIgnored private let onMultiSelect: @MainActor () -> Void

    init(
        announce: @escaping @MainActor (String) -> Void = LayoutSelectionModel.postAnnouncement,
        onMultiSelect: @escaping @MainActor () -> Void = {}
    ) {
        self.announce = announce
        self.onMultiSelect = onMultiSelect
    }

    var count: Int {
        selection.count
    }

    func contains(_ itemID: String) -> Bool {
        selection.contains(itemID)
    }

    /// The selected items left to right as they sit in the menu bar.
    var orderedItemIDs: [String] {
        selection.orderedItemIDs(in: units)
    }

    /// Records what a section's bar shows now and deselects anything it no longer shows.
    func update(_ units: [Unit], in section: MenuBarSectionName) {
        self.units[section] = units
        change(announcing: false) { $0.retain(units, in: section) }
    }

    func click(_ itemID: String, in section: MenuBarSectionName, kind: LayoutSelection.Click) {
        let previousCount = count
        change { $0.click(itemID, in: section, units: units[section] ?? [], kind: kind) }
        if Self.isMultiSelection(kind, from: previousCount, to: count) {
            onMultiSelect()
        }
    }

    /// Whether a click of kind that took the selection from oldCount to newCount items made a multi-selection.
    /// A plain click on a group selects several items too, but it is not the user selecting several.
    nonisolated static func isMultiSelection(_ kind: LayoutSelection.Click, from oldCount: Int, to newCount: Int) -> Bool {
        kind != .replace && oldCount < 2 && newCount >= 2
    }

    func clear() {
        change { $0.clear() }
    }

    /// The move of the whole selection to section, or nil when nothing is selected.
    func command(to section: MenuBarSectionName, placement: LayoutBatchMove.Placement) -> LayoutBatchMove? {
        let itemIDs = orderedItemIDs
        guard !itemIDs.isEmpty else { return nil }
        return LayoutBatchMove(itemIDs: itemIDs, section: section, placement: placement)
    }

    /// Whether section would take the whole selection.
    func accepts(_ section: MenuBarSectionName, in snapshot: LayoutBatchMoveSnapshot) -> Bool {
        guard let command = command(to: section, placement: .end) else { return false }
        return (try? command.plan(in: snapshot).get()) != nil
    }

    /// The sections a context menu offers to move the selection to.
    func moveTargets(in snapshot: LayoutBatchMoveSnapshot) -> [MenuBarSectionName] {
        let enabled = MenuBarSectionName.allCases.filter { snapshot.sections[$0] != nil }
        return selection.moveTargets(enabledSections: enabled) { accepts($0, in: snapshot) }
    }

    /// Moves the selection in one batch and clears it. Nil when nothing is selected.
    func move(
        to section: MenuBarSectionName,
        placement: LayoutBatchMove.Placement,
        using mover: Mover
    ) async -> LayoutBatchMoveOutcome? {
        guard let command = command(to: section, placement: placement) else { return nil }
        clear()
        return await mover(command)
    }

    /// Applies body to the selection and, when announcing, tells VoiceOver if the count changed.
    private func change(announcing: Bool = true, _ body: (inout LayoutSelection) -> Void) {
        var updated = selection
        body(&updated)
        guard updated != selection else { return }
        let previousCount = selection.count
        selection = updated
        if announcing, updated.count != previousCount {
            announce(Self.announcement(count: updated.count))
        }
    }

    nonisolated static func announcement(count: Int) -> String {
        count == 0
            ? String(localized: "Selection cleared", comment: "VoiceOver announcement when the Layout pane's selection is cleared")
            : String(localized: "\(count) items selected", comment: "VoiceOver announcement of how many items are selected in the Layout pane")
    }

    /// What the pane says when a move of the selection was refused. Nil for a move that went through.
    nonisolated static func refusal(
        for outcome: LayoutBatchMoveOutcome,
        section: MenuBarSectionName,
        itemName: (String) -> String?
    ) -> LayoutBarFeedbackCenter.Refusal? {
        guard case let .refused(error) = outcome else { return nil }
        switch error {
        case let .controlItem(id), let .notMovable(id, _):
            if let name = itemName(id) {
                return LayoutBarFeedbackCenter.itemCannotMove(itemName: name, section: section)
            }
        default:
            break
        }
        return LayoutBarFeedbackCenter.Refusal(
            title: String(
                localized: "The selected items couldn’t move to \(section.localizedName)",
                comment: "Title shown when a move of several selected Layout items was refused"
            ),
            message: String(
                localized: "Nothing was moved. An item may have quit or changed since you selected it. Select the items again and retry.",
                comment: "Explanation shown when a move of several selected Layout items was refused"
            )
        )
    }

    static func postAnnouncement(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }
}
