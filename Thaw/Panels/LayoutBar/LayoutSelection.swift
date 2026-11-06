//
//  LayoutSelection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// The Layout pane's selection and its rules, on identifiers only, with each group as one unit.
nonisolated struct LayoutSelection: Equatable, Sendable {
    /// One thing a click selects: a single item, or every member of a group.
    struct Unit: Equatable, Sendable {
        let memberIDs: [String]
        /// False for Thaw's own control items and items that cannot move anywhere.
        let isSelectable: Bool
    }

    /// How a click changes the selection.
    enum Click: Equatable, Sendable {
        /// Selects just the clicked unit.
        case replace
        /// Adds the clicked unit, or removes it when it is already selected.
        case toggle
        /// Adds every selectable unit from the anchor to the clicked unit, in one section.
        case extend

        /// Command toggles and wins over Shift, which extends; a plain click replaces.
        init(command: Bool, shift: Bool) {
            if command {
                self = .toggle
            } else if shift {
                self = .extend
            } else {
                self = .replace
            }
        }
    }

    /// The item a Shift click starts its range from.
    struct Anchor: Equatable, Sendable {
        let section: MenuBarSectionName
        let itemID: String
    }

    /// The sections left to right as they sit in the menu bar, which is the order a batch keeps.
    static let barOrder: [MenuBarSectionName] = [.alwaysHidden, .hidden, .visible]

    private(set) var itemIDs = [MenuBarSectionName: Set<String>]()
    /// The item the last plain or Command click landed on.
    private(set) var anchor: Anchor?

    var count: Int {
        itemIDs.values.reduce(0) { $0 + $1.count }
    }

    var isEmpty: Bool {
        itemIDs.values.allSatisfy(\.isEmpty)
    }

    func contains(_ itemID: String) -> Bool {
        itemIDs.values.contains { $0.contains(itemID) }
    }

    /// The sections that hold at least one selected item.
    var sections: Set<MenuBarSectionName> {
        Set(itemIDs.filter { !$0.value.isEmpty }.keys)
    }

    mutating func clear() {
        itemIDs = [:]
        anchor = nil
    }

    /// Applies a click on itemID in section, whose units are listed left to right.
    mutating func click(_ itemID: String, in section: MenuBarSectionName, units: [Unit], kind: Click) {
        guard let index = units.firstIndex(where: { $0.memberIDs.contains(itemID) }), units[index].isSelectable else {
            if kind == .replace {
                clear()
            }
            return
        }
        let members = Set(units[index].memberIDs)
        switch kind {
        case .replace:
            itemIDs = [section: members]
            anchor = Anchor(section: section, itemID: itemID)
        case .toggle:
            if members.isSubset(of: itemIDs[section] ?? []) {
                itemIDs[section]?.subtract(members)
            } else {
                itemIDs[section, default: []].formUnion(members)
            }
            anchor = Anchor(section: section, itemID: itemID)
        case .extend:
            guard let anchor, anchor.section == section,
                  let start = units.firstIndex(where: { $0.memberIDs.contains(anchor.itemID) })
            else {
                click(itemID, in: section, units: units, kind: .replace)
                return
            }
            for unit in units[min(start, index) ... max(start, index)] where unit.isSelectable {
                itemIDs[section, default: []].formUnion(unit.memberIDs)
            }
        }
        if itemIDs[section]?.isEmpty == true {
            itemIDs[section] = nil
        }
    }

    /// Deselects the items a section no longer shows as selectable, after its items were read again.
    mutating func retain(_ units: [Unit], in section: MenuBarSectionName) {
        let present = Set(units.filter(\.isSelectable).flatMap(\.memberIDs))
        if let selected = itemIDs[section] {
            let kept = selected.intersection(present)
            itemIDs[section] = kept.isEmpty ? nil : kept
        }
        if let anchor, anchor.section == section, !present.contains(anchor.itemID) {
            self.anchor = nil
        }
    }

    /// The selected items left to right as they sit in the menu bar, given each section's units.
    func orderedItemIDs(in layout: [MenuBarSectionName: [Unit]]) -> [String] {
        Self.barOrder.flatMap { section in
            let selected = itemIDs[section] ?? []
            return (layout[section] ?? []).flatMap(\.memberIDs).filter { selected.contains($0) }
        }
    }

    /// The enabled sections the selection is not wholly in already and would be accepted by.
    func moveTargets(
        enabledSections: [MenuBarSectionName],
        accepts: (MenuBarSectionName) -> Bool
    ) -> [MenuBarSectionName] {
        guard !isEmpty else { return [] }
        return enabledSections.filter { sections != [$0] && accepts($0) }
    }

    /// A drop at index lands after the nearest unselected item before it, or at the start.
    static func placement(
        insertingAt index: Int,
        in order: [String],
        selected: Set<String>
    ) -> LayoutBatchMove.Placement {
        let before = order.prefix(max(0, index))
        if let anchor = before.last(where: { !selected.contains($0) }) {
            return .after(anchor)
        }
        return .start
    }
}
