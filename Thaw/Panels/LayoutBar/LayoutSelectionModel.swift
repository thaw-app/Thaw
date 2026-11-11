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
        onMultiSelect: @escaping @MainActor () -> Void = { /* Callers that don't react to multiple selection pass nothing. */ }
    ) {
        self.announce = announce
        self.onMultiSelect = onMultiSelect
    }

    var count: Int {
        selection.count
    }

    /// The item the last plain or Command click landed on, where the keyboard works from.
    var anchorItemID: String? {
        selection.anchor?.itemID
    }

    /// How many times the selection changed; tests use it to catch a feedback loop.
    @ObservationIgnored private(set) var changeCount = 0

    func contains(_ itemID: String) -> Bool {
        selection.contains(itemID)
    }

    /// The selected items left to right as they sit in the menu bar.
    var orderedItemIDs: [String] {
        selection.orderedItemIDs(in: units)
    }

    /// Moved items to select again once their new section's bar lists them.
    @ObservationIgnored private var pendingReselection: (itemIDs: [String], section: MenuBarSectionName)?

    /// Records what a section's bar shows now and deselects anything it no longer shows.
    func update(_ units: [Unit], in section: MenuBarSectionName) {
        self.units[section] = units
        change(announcing: false) { $0.retain(units, in: section) }
        applyPendingReselection()
    }

    /// Selects itemIDs in section again after a move, now if its bar lists them already,
    /// otherwise when it next reports them. The keyboard keeps working on what it moved.
    func reselect(_ itemIDs: [String], in section: MenuBarSectionName) {
        guard !itemIDs.isEmpty else { return }
        pendingReselection = (itemIDs, section)
        applyPendingReselection()
    }

    private func applyPendingReselection() {
        guard let pending = pendingReselection else { return }
        let shown = Set((units[pending.section] ?? []).flatMap(\.memberIDs))
        guard pending.itemIDs.allSatisfy(shown.contains) else { return }
        pendingReselection = nil
        let sectionUnits = units[pending.section] ?? []
        change(announcing: false) { selection in
            selection.click(pending.itemIDs[0], in: pending.section, units: sectionUnits, kind: .replace)
            for id in pending.itemIDs.dropFirst() where !selection.contains(id) {
                selection.click(id, in: pending.section, units: sectionUnits, kind: .toggle)
            }
        }
    }

    func click(_ itemID: String, in section: MenuBarSectionName, kind: LayoutSelection.Click) {
        click(itemID, in: section, kind: kind, among: nil)
    }

    /// A click whose extend reaches only the listed items, so a filtered list never selects rows it
    /// isn't showing. The anchor's unit stays reachable, so a range can start from a row since hidden.
    func click(_ itemID: String, in section: MenuBarSectionName, kind: LayoutSelection.Click, among visibleIDs: Set<String>?) {
        pendingReselection = nil
        let previousCount = count
        let sectionUnits = units[section] ?? []
        let clickUnits: [Unit]
        if let visibleIDs {
            let anchorID = selection.anchor?.itemID
            clickUnits = sectionUnits.filter { unit in
                unit.memberIDs.contains(where: visibleIDs.contains) || (anchorID.map(unit.memberIDs.contains) ?? false)
            }
        } else {
            clickUnits = sectionUnits
        }
        change { $0.click(itemID, in: section, units: clickUnits, kind: kind) }
        if Self.isMultiSelection(kind, from: previousCount, to: count) {
            onMultiSelect()
        }
    }

    /// Whether a click of kind that took the selection from oldCount to newCount items made a multi-selection.
    /// A plain click on a group selects several items too, but it is not the user selecting several.
    static nonisolated func isMultiSelection(_ kind: LayoutSelection.Click, from oldCount: Int, to newCount: Int) -> Bool {
        kind != .replace && oldCount < 2 && newCount >= 2
    }

    /// Like a click, clearing or selecting drops a reselection still waiting for its bar, so a late bar update can't override it.
    func clear() {
        pendingReselection = nil
        change { $0.clear() }
    }

    /// Selects every item the bars show.
    func selectAll() {
        pendingReselection = nil
        change { $0.selectAll(in: units) }
    }

    /// Selects only the listed items, so ⌘A in a filtered list leaves out the rows it hides.
    func selectAll(among itemIDs: Set<String>) {
        pendingReselection = nil
        change { $0.selectAll(among: itemIDs, in: units) }
    }

    /// Selects the items the bars show among itemIDs, such as a group's members.
    func select(_ itemIDs: [String]) {
        pendingReselection = nil
        change { $0.select(Set(itemIDs), in: units) }
    }

    /// The sections holding a selected item.
    var sections: Set<MenuBarSectionName> {
        selection.sections
    }

    /// The units a section's bar last reported, left to right.
    func units(in section: MenuBarSectionName) -> [Unit] {
        units[section] ?? []
    }

    /// The move of the whole selection to section, or nil when nothing is selected.
    func command(to section: MenuBarSectionName, placement: LayoutBatchMove.Placement) -> LayoutBatchMove? {
        let itemIDs = orderedItemIDs
        guard !itemIDs.isEmpty else { return nil }
        return LayoutBatchMove(itemIDs: itemIDs, section: section, placement: placement)
    }

    /// One move per selected unit, left to right, that puts it back after its old left neighbour.
    /// A group restores as one move, since the move planner takes a group only whole.
    func restoringMoves() -> [LayoutBatchMove] {
        let selected = Set(orderedItemIDs)
        return MenuBarSectionName.allCases.flatMap { section -> [LayoutBatchMove] in
            let sectionUnits = units[section] ?? []
            return sectionUnits.indices.compactMap { index -> LayoutBatchMove? in
                let unit = sectionUnits[index]
                guard unit.memberIDs.contains(where: selected.contains) else { return nil }
                let anchor = sectionUnits[..<index].reversed().first(where: { !$0.memberIDs.isEmpty })?.memberIDs.last
                let placement = anchor.map(LayoutBatchMove.Placement.after) ?? .start
                return LayoutBatchMove(itemIDs: unit.memberIDs, section: section, placement: placement)
            }
        }
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

    /// Puts back a selection that a move cleared, unless something was selected since.
    func restore(_ previous: LayoutSelection) {
        guard selection.isEmpty else { return }
        pendingReselection = nil
        change(announcing: false) { $0 = previous }
    }

    /// Whether a move left every item where it was: refused, or nothing to change.
    static nonisolated func leftItemsInPlace(_ outcome: LayoutBatchMoveOutcome?) -> Bool {
        switch outcome {
        case .refused, .unchanged: true
        case .moved, .notApplied, nil: false
        }
    }

    /// Applies body to the selection and, when announcing, tells VoiceOver if the count changed.
    private func change(announcing: Bool = true, _ body: (inout LayoutSelection) -> Void) {
        var updated = selection
        body(&updated)
        guard updated != selection else { return }
        let previousCount = selection.count
        changeCount += 1
        selection = updated
        if announcing, updated.count != previousCount {
            announce(Self.announcement(count: updated.count))
        }
    }

    /// What VoiceOver says when a move of the selection lands.
    static nonisolated func movedAnnouncement(count: Int, to section: MenuBarSectionName) -> String {
        String(AttributedString(
            localized: "Moved ^[\(count) item](inflect: true) to \(section.localizedName)",
            comment: "VoiceOver announcement after selected Layout items moved to a section"
        ).characters)
    }

    static nonisolated func announcement(count: Int) -> String {
        count == 0
            ? String(localized: "Selection cleared", comment: "VoiceOver announcement when the Layout pane's selection is cleared")
            : String(localized: "\(count) items selected", comment: "VoiceOver announcement of how many items are selected in the Layout pane")
    }

    /// What the pane says when a move of the selection was refused. Nil for a move that went through.
    static nonisolated func refusal(
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
