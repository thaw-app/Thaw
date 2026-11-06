//
//  MoveLanding.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Whether a move chosen from an item's menu left the item in the section it was sent to.
enum MoveLanding {
    /// The stored weights decide when they can be read, since an assignment can hold while a failed
    /// weight write leaves the item on the old side of a divider. Otherwise the assignment decides.
    nonisolated static func landed(
        in target: MenuBarSectionName,
        assigned: MenuBarSectionName,
        observed: MenuBarSectionName?
    ) -> Bool {
        (observed ?? assigned) == target
    }

    /// The section the item's stored weight puts it in on the bar.
    /// Nil when the weights can't be read, the item has none, or its weight parks it off the bar.
    @MainActor
    static func observedSection(
        of item: MenuBarItem,
        liveItems: [MenuBarItem],
        dividers: ControlItemPair?,
        table: StoredWeights.Table = .read()
    ) -> MenuBarSectionName? {
        guard let reading = ObservedMembership.storedReading(liveItems: liveItems, dividers: dividers, table: table),
              let weight = reading.weights.weight(of: item),
              !reading.weights.isParked(weight)
        else { return nil }
        return reading.dividers.section(for: weight)
    }
}
