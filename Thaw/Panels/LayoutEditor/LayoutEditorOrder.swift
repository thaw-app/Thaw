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

    /// Merges the achievable on-screen order into the saved order. Off-screen entries keep their
    /// slots, and an entry the saved order lacks goes after its predecessor, or first.
    static func mergingAchievableOrder(_ achievable: [String], into saved: [String]) -> [String] {
        let achievableSet = Set(achievable)
        let savedSet = Set(saved)
        var fill = achievable.filter { savedSet.contains($0) }.makeIterator()
        var result = saved.map { id in
            achievableSet.contains(id) ? (fill.next() ?? id) : id
        }
        return insertingUnnamed(achievable, into: result)
    }

    /// Adds the live items an order leaves out, each after its live predecessor or first, matched by
    /// canonical spelling. The kit writes nothing for a section whose order omits a live item.
    static func completingOrder(_ order: [String], withLive live: [String]) -> [String] {
        insertingUnnamed(live, into: order, key: MenuBarItemTag.canonicalPersistentIdentifier)
    }

    /// Inserts each entry of ordered that base lacks after the entry that precedes it in ordered, or first.
    private static func insertingUnnamed(
        _ ordered: [String],
        into base: [String],
        key: (String) -> String = { $0 }
    ) -> [String] {
        let named = Set(base.map(key))
        var result = base
        for (index, id) in ordered.enumerated() where !named.contains(key(id)) {
            let at = index > 0
                ? result.firstIndex { key($0) == key(ordered[index - 1]) }.map { $0 + 1 }
                : 0
            result.insert(id, at: at ?? result.endIndex)
        }
        return result
    }

    /// The merged Visible order as live items, off-screen ones included. An identifier with no live
    /// item drops out, because the kit restores saved entries for apps that are not running.
    static func itemsMergingAchievableOrder(
        _ achievable: [String],
        into saved: [String],
        candidates: [MenuBarItem]
    ) -> [MenuBarItem] {
        let merged = mergingAchievableOrder(
            MenuBarItemTag.canonicalPersistentIdentifiers(achievable),
            into: saved
        )
        let byIdentifier = Dictionary(
            candidates.map { (MenuBarItemTag.canonicalPersistentIdentifier($0.uniqueIdentifier), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return merged.compactMap { byIdentifier[$0] }
    }
}
