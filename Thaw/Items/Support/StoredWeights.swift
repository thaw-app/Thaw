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
    /// The position table as one read left it. Each read forces a preferences sync, so a caller that
    /// asks again and again while nothing of Thaw's writes, such as a poll waiting out a reflow, reads once.
    struct Table {
        fileprivate let isAvailable: Bool
        fileprivate let positions: [String: Int]
        fileprivate let keys: [String]

        @MainActor
        static func read() -> Table {
            let store = MenuBarPositionStoreProvider.current
            let isAvailable = store.positionsDomainIsAccessible()
            let positions = isAvailable ? store.currentPositions() : [:]
            return Table(isAvailable: isAvailable, positions: positions, keys: Array(positions.keys))
        }
    }

    private let store = MenuBarPositionStoreProvider.current
    private let positions: [String: Int]
    private let keys: [String]
    private let items: [MenuBarItem]

    /// False when the table could not be read. Every weight is nil then.
    let isAvailable: Bool

    init(among items: [MenuBarItem], table: Table = .read()) {
        self.items = items
        isAvailable = table.isAvailable
        positions = table.positions
        keys = table.keys
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
