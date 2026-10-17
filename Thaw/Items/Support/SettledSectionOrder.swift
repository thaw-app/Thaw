//
//  SettledSectionOrder.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Whether a concealed section's members already sit in the stored order, each on its side of the dividers.
/// A respace then only changes the gaps, and each one nudges MenuBarAgent to lay out the bar again.
enum SettledSectionOrder {
    private static let diagLog = DiagLog(category: "SettledSectionOrder")

    /// The weights run left to right in the section's desired order.
    nonisolated static func isInOrder(
        _ weights: [Int?],
        section: MenuBarSectionName,
        dividers: ObservedMembership.Dividers
    ) -> Bool {
        let known = weights.compactMap(\.self)
        guard known.count > 1, known.count == weights.count,
              known.allSatisfy({ dividers.section(for: $0) == section })
        else { return false }
        let leftIsHigher = dividers.hidden > dividers.visibleControl
        return zip(known, known.dropFirst()).allSatisfy { leftIsHigher ? $0 > $1 : $0 < $1 }
    }

    @MainActor
    static func isStored(
        section: MenuBarSectionName,
        desiredOrder: [String],
        liveItems: [MenuBarItem],
        dividers: ControlItemPair?,
        table: StoredWeights.Table = .read()
    ) -> Bool {
        guard section != .visible,
              let (ordered, weights, items) = ObservedMembership.storedReading(liveItems: liveItems, dividers: dividers, table: table)
        else { return false }
        let members = desiredOrder.map { identifier in
            items.first { $0.uniqueIdentifier == identifier }.flatMap(weights.weight(of:))
        }
        let settled = isInOrder(members, section: section, dividers: ordered)
        if settled {
            diagLog.debug("section apply \(section.logString): stored order already matches; not rewriting")
        }
        return settled
    }
}
