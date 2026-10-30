//
//  MenuBarItemAXProvider+SavedIdentities.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import os.lock

nonisolated extension MenuBarItemAXProvider {
    /// Gives items that answered under a placeholder name their saved identity, so every consumer
    /// sees the same one. See PlaceholderIdentityAdoption.
    ///
    /// This runs on every walk, so the saved order is read only when such an item is present.
    ///
    /// - Parameter savedOrder: Reads the saved section order the identities come from.
    static func adoptingSavedIdentities(
        _ items: [MenuBarItem],
        savedOrder: () -> [String: [String]] = { SavedSectionOrderDefaults.read() }
    ) -> [MenuBarItem] {
        guard items.contains(where: PlaceholderIdentityAdoption.hasPlaceholderIdentity) else {
            lastAdoptedIdentities.withLock { $0 = [:] }
            return items
        }
        let result = PlaceholderIdentityAdoption.adopting(
            items,
            savedTitles: PlaceholderIdentityAdoption.savedTitles(in: savedOrder())
        )
        let changed = lastAdoptedIdentities.withLock { last in
            guard last != result.adopted else { return false }
            last = result.adopted
            return true
        }
        if changed, !result.adopted.isEmpty {
            let pairs = result.adopted.sorted { $0.key < $1.key }.map { "\($0.key) -> \($0.value)" }
            adoptionLog.info("menuBarItems: \(pairs.count) item(s) answered under a placeholder name; using the saved identity: \(pairs)")
        }
        return result.items
    }

    /// The adoptions last logged, so a standing one is logged once rather than on every walk.
    private static let lastAdoptedIdentities = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

    private static let adoptionLog = DiagLog(category: "MenuBarItemAXProvider")
}
