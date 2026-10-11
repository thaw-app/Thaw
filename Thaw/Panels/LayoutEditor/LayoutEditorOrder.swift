//
//  LayoutEditorOrder.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// The ordering rules of the reorder editor, on identifiers only so they run without a menu bar.
nonisolated enum LayoutEditorOrder {
    /// One thing the editor drags: a single item, or a group that moves as a block.
    struct Unit: Identifiable, Equatable {
        let id: String
        let memberIDs: [String]

        var isGroup: Bool {
            memberIDs.count > 1
        }
    }

    /// What a drop changes.
    struct Change: Equatable {
        let source: MenuBarSectionName
        let target: MenuBarSectionName
        let movedIDs: [String]
        /// Each section's units once the drop is applied.
        let units: [MenuBarSectionName: [Unit]]

        func itemIDs(in section: MenuBarSectionName) -> [String] {
            (units[section] ?? []).flatMap(\.memberIDs)
        }
    }

    /// Folds a section's items into units. A group sits where its first member is,
    /// since members can be scattered until a move gathers them.
    static func units(itemIDs: [String], groups: [(id: String, memberIndices: [Int])]) -> [Unit] {
        var groupAtIndex = [Int: Int]()
        for (groupIndex, group) in groups.enumerated() where group.memberIndices.count > 1 {
            for index in group.memberIndices where itemIDs.indices.contains(index) {
                groupAtIndex[index] = groupIndex
            }
        }
        var emitted = Set<Int>()
        var units = [Unit]()
        for (index, itemID) in itemIDs.enumerated() {
            guard let groupIndex = groupAtIndex[index] else {
                units.append(Unit(id: itemID, memberIDs: [itemID]))
                continue
            }
            guard emitted.insert(groupIndex).inserted else { continue }
            let group = groups[groupIndex]
            let members = group.memberIndices.filter { itemIDs.indices.contains($0) }.map { itemIDs[$0] }
            units.append(Unit(id: "group:\(group.id)", memberIDs: members))
        }
        return units
    }

    /// The result of dropping a unit in a section, before another unit or at the end.
    /// Nil when the unit is unknown or the drop leaves everything where it was.
    static func change(
        moving unitID: String,
        in units: [MenuBarSectionName: [Unit]],
        to target: MenuBarSectionName,
        before beforeID: String?
    ) -> Change? {
        guard let source = units.first(where: { $0.value.contains { $0.id == unitID } })?.key,
              let unit = units[source]?.first(where: { $0.id == unitID }),
              beforeID != unitID
        else {
            return nil
        }
        var result = units
        result[source]?.removeAll { $0.id == unitID }
        var list = result[target] ?? []
        let index = beforeID.flatMap { id in list.firstIndex { $0.id == id } } ?? list.endIndex
        list.insert(unit, at: index)
        result[target] = list
        guard result != units else { return nil }
        return Change(source: source, target: target, movedIDs: unit.memberIDs, units: result)
    }

    /// Whether the editor should keep showing the order it was given by a drop
    /// instead of the order read back from the menu bar, which lags the move.
    static func keepsAuthoredOrder(authored: [String], live: [String], elapsed: Duration, limit: Duration) -> Bool {
        guard elapsed < limit, authored != live else { return false }
        // A different set means an item came or went; the authored order is stale.
        return Set(authored) == Set(live)
    }
}
