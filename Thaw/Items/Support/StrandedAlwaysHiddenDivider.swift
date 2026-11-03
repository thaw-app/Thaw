//
//  StrandedAlwaysHiddenDivider.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import PlatformRuntimeKit

/// Puts Thaw's Always Hidden divider back left of the Hidden section when its weight
/// falls among the Hidden or Visible items, where it conceals everything left of it.
///
/// The table can file the divider under Thaw's bundle identifier and under its name, and
/// the kit seats only the row it resolves, so every one of Thaw's own rows is checked here.
enum StrandedAlwaysHiddenDivider {
    private static let diagLog = DiagLog(category: "StrandedAlwaysHiddenDivider")

    /// New weights for the divider rows that sort right of the leftmost Hidden-side weight.
    /// A tie is left alone. No member's weight changes.
    ///
    /// - Parameters:
    ///   - dividerKeys: Thaw's own rows for the Always Hidden divider; empty when it is off.
    ///   - hiddenSideKeys: the Hidden divider's row and every Hidden item's row.
    ///   - ascending: whether higher weights sort further right.
    static nonisolated func reseatedWeights(
        dividerKeys: [String],
        alwaysHiddenItemKeys: [String],
        hiddenSideKeys: [String],
        in positions: [String: Int],
        ascending: Bool
    ) -> [String: Int] {
        let hiddenSide = hiddenSideKeys.compactMap { positions[$0] }
        guard let after = ascending ? hiddenSide.min() : hiddenSide.max() else { return [:] }
        let alwaysHiddenSide = alwaysHiddenItemKeys.compactMap { positions[$0] }
            .filter { ascending ? $0 < after : $0 > after }
        let before = ascending ? alwaysHiddenSide.max() : alwaysHiddenSide.min()
        var weights = [String: Int]()
        let taken = Set(positions.values)
        for key in Set(dividerKeys) {
            guard let weight = positions[key], ascending ? weight > after : weight < after else { continue }
            weights[key] = ControlItemSeating.seat(between: before, and: after, ascending: ascending, avoiding: taken)
        }
        return weights
    }

    /// The owner names the table may file Thaw's rows under.
    static nonisolated func ownerNames(of bundle: Bundle = .main) -> [String] {
        [
            bundle.bundleIdentifier,
            bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
        ].compactMap(\.self)
    }

    /// Writes the stranded divider rows back left of the Hidden section.
    ///
    /// - Returns: the divider's identifier when a row was written, otherwise an empty list.
    @MainActor
    static func reseat(
        _ divider: MenuBarItem?,
        rightOf alwaysHiddenItems: [MenuBarItem],
        leftOf hiddenSide: [MenuBarItem],
        liveItems: [MenuBarItem],
        owners: [String] = ownerNames(),
        store: PermittedPositionStore = MenuBarPositionStoreProvider.current,
        permit: borrowing StoreWritePermit
    ) -> [String] {
        guard let divider else { return [] }
        let positions = store.readPositions()
        let existingKeys = Array(positions.keys)
        func key(_ item: MenuBarItem) -> String? {
            store.resolveKey(for: item, existingKeys: existingKeys, positions: positions, liveItems: liveItems)
        }
        let members = liveItems.filter { !$0.isControlItem && $0.isOnScreen }.compactMap { item in
            key(item).flatMap { positions[$0] }.map { (x: item.bounds.midX, weight: $0) }
        }
        let ascending = ControlItemSeating.axisAscends(members: members)
            ?? RuntimePreferenceKeys.storeAxisAscending(in: positions)
            ?? true
        let weights = reseatedWeights(
            dividerKeys: owners.map { "status:\($0)::\(divider.tag.title)" } + [key(divider)].compactMap(\.self),
            alwaysHiddenItemKeys: alwaysHiddenItems.compactMap(key),
            hiddenSideKeys: hiddenSide.compactMap(key).filter { !store.isParkedWeight(positions[$0] ?? 0) },
            in: positions,
            ascending: ascending
        )
        guard !weights.isEmpty else { return [] }
        store.writePositions(positions.merging(weights) { $1 }, permit: permit)
        diagLog.info("reseated the Always Hidden divider left of the Hidden section: \(weights)")
        return [divider.uniqueIdentifier]
    }
}
