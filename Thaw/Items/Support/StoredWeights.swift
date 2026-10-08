//
//  StoredWeights.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// The weights MenuBarAgent sorts a set of live items by, read from the position table once.
@MainActor
struct StoredWeights {
    private let store = MenuBarPositionStoreProvider.current
    private let positions: [String: Int]
    private let keys: [String]
    private let items: [MenuBarItem]

    /// False when the table could not be read. Every weight is nil then.
    let isAvailable: Bool

    init(among items: [MenuBarItem]) {
        self.items = items
        isAvailable = store.positionsDomainIsAccessible()
        positions = isAvailable ? store.currentPositions() : [:]
        keys = Array(positions.keys)
    }

    func weight(of item: MenuBarItem) -> Int? {
        store.resolveKey(for: item, existingKeys: keys, positions: positions, liveItems: items)
            .flatMap { positions[$0] }
    }

    /// Whether a weight is one of the far-off values that park an item off the bar.
    func isParked(_ weight: Int) -> Bool {
        store.isParkedWeight(weight)
    }
}
