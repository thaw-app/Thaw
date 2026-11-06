//
//  MenuBarItemManager+VolatileTitles.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

extension MenuBarItemManager {
    /// Keeps each app's last fresh scan between refreshes.
    private static var freshVolatileTitleLearner = FreshVolatileTitleLearner()

    private static let learnedVolatileTitleOwnersKey = "MenuBarItemManager.learnedVolatileTitleOwners"

    /// Restore learned owners before canonicalization so known and saved-order identifiers load collapsed.
    func loadLearnedVolatileTitleOwners() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.learnedVolatileTitleOwnersKey) ?? []
        let kept = stored.filter { !Self.isThawBundle($0) }
        if kept.count != stored.count {
            UserDefaults.standard.set(kept, forKey: Self.learnedVolatileTitleOwnersKey)
        }
        MenuBarItemTag.restoreLearnedVolatileTitleOwners(Set(kept))
    }

    /// Thaw's fixed autosave names identify different items, not retitles.
    /// Learning these bundles would collapse distinct controls into one identity.
    private static func isThawBundle(_ bundleID: String) -> Bool {
        let thaw = ThawMenuBarIdentity.bundleIdentifier
        return bundleID == thaw || bundleID.hasPrefix(thaw + ".")
    }

    /// Collapse retitled single-item owners so changing counts or dates do not trigger new-arrival sorting.
    /// Takes fresh answers only: the cache keeps old titles, which look like extra items.
    func learnVolatileTitleOwners(fresh: [MenuBarItem], current: inout [MenuBarItem]) {
        let learned = Self.freshVolatileTitleLearner.observe(fresh)
            .filter { !Self.isThawBundle($0) }
            .filter(MenuBarItemTag.learnVolatileTitleOwner)
        guard !learned.isEmpty else { return }

        MenuBarItemManager.diagLog.info("Learned retitling owners: \(learned.sorted())")
        UserDefaults.standard.set(
            MenuBarItemTag.learnedVolatileTitleOwners.sorted(),
            forKey: Self.learnedVolatileTitleOwnersKey
        )
        // Canonicalize known and current identities now so this walk does not report a new arrival.
        knownItemIdentifiers = Set(knownItemIdentifiers.map(MenuBarItemTag.canonicalPersistentIdentifier))
        persistKnownItemIdentifiers()
        persistSavedSectionOrder()
        for (index, item) in current.enumerated() {
            guard case let .string(bundleID) = item.tag.namespace, learned.contains(bundleID) else { continue }
            let tag = MenuBarItemTag(
                namespace: item.tag.namespace,
                title: MenuBarItemTag.canonicalTitle(namespace: item.tag.namespace, title: item.tag.title),
                windowID: item.tag.windowID,
                instanceIndex: item.tag.instanceIndex
            )
            current[index] = MenuBarItem(
                tag: tag,
                windowID: item.windowID,
                ownerPID: item.ownerPID,
                sourcePID: item.sourcePID,
                bounds: item.bounds,
                title: item.title,
                isOnScreen: item.isOnScreen
            )
        }
    }
}
