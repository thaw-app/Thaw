//
//  MenuBarItemManager+VolatileTitles.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

extension MenuBarItemManager {
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
    /// Siblings are ambiguous; transitions to or from Item-N indicate launch completion, not retitling.
    func learnVolatileTitleOwners(previous: [MenuBarItem], current: inout [MenuBarItem]) {
        let previousByOwner = Self.singleItemsByOwner(previous)
        let currentByOwner = Self.singleItemsByOwner(current)
        var learned = [String: MenuBarItem]()
        for (bundleID, item) in currentByOwner {
            guard !Self.isThawBundle(bundleID),
                  let before = previousByOwner[bundleID],
                  before.tag.title != item.tag.title,
                  !before.tag.title.isEmpty,
                  !item.tag.title.isEmpty,
                  !MenuBarItemTag.isGenericItemTitle(before.tag.title),
                  !MenuBarItemTag.isGenericItemTitle(item.tag.title),
                  MenuBarItemTag.learnVolatileTitleOwner(bundleID)
            else {
                continue
            }
            learned[bundleID] = before
        }
        guard !learned.isEmpty else { return }

        MenuBarItemManager.diagLog.info("Learned retitling owners: \(learned.keys.sorted())")
        UserDefaults.standard.set(
            MenuBarItemTag.learnedVolatileTitleOwners.sorted(),
            forKey: Self.learnedVolatileTitleOwnersKey
        )
        // Canonicalize known and current identities now so this walk does not report a new arrival.
        for item in learned.values {
            knownItemIdentifiers.insert(item.uniqueIdentifier)
        }
        knownItemIdentifiers = Set(knownItemIdentifiers.map(MenuBarItemTag.canonicalPersistentIdentifier))
        persistKnownItemIdentifiers()
        persistSavedSectionOrder()
        for (index, item) in current.enumerated() {
            guard case let .string(bundleID) = item.tag.namespace, learned[bundleID] != nil else { continue }
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

    private static func singleItemsByOwner(_ items: [MenuBarItem]) -> [String: MenuBarItem] {
        var byOwner = [String: [MenuBarItem]]()
        for item in items where !item.isControlItem && !item.isSystemClone && item.sourcePID != nil {
            guard case let .string(bundleID) = item.tag.namespace,
                  !MenuBarItemTag.hasCanonicalizableTitles(bundleID)
            else {
                continue
            }
            byOwner[bundleID, default: []].append(item)
        }
        return byOwner.compactMapValues { $0.count == 1 ? $0[0] : nil }
    }
}
