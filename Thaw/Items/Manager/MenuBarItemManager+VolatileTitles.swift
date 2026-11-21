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

    /// The one follow-up read waiting to run, and how many each app has left.
    private static var retitleFollowUps = RetitleFollowUpSchedule()

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

    /// Reads the bar once more if it stays quiet, because a new title alone starts no read and the
    /// learner needs one on each side of the change. RetitleFollowUpSchedule limits these per app.
    private func scheduleRetitleFollowUp() {
        let candidates = Self.freshVolatileTitleLearner.comparableOwners.filter { !Self.isThawBundle($0) }
        guard let delay = Self.retitleFollowUps.claim(candidates: candidates) else { return }
        Self.retitleFollowUps.arm(Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay, tolerance: .seconds(5))
            } catch {
                return
            }
            // A newer read cancels this wait, and the cancel can land just after the sleep returns.
            guard !Task.isCancelled, let self else { return }
            Self.retitleFollowUps.fired()
            MenuBarItemManager.diagLog.debug("Reading the bar again in case \(candidates.sorted()) renamed an item")
            await cacheItemsRegardless()
        })
    }

    /// Collapse retitled single-item owners so changing counts or dates do not trigger new-arrival sorting.
    /// Takes fresh answers only: the cache keeps old titles, which look like extra items.
    func learnVolatileTitleOwners(fresh: [MenuBarItem], current: inout [MenuBarItem]) {
        let learned = Self.freshVolatileTitleLearner.observe(fresh, displays: BarAxis.liveDisplayBounds())
            .filter { !Self.isThawBundle($0) }
            .filter(MenuBarItemTag.learnVolatileTitleOwner)
        scheduleRetitleFollowUp()
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
            guard let bundleID = item.tag.namespace.bundleIdentifier, learned.contains(bundleID) else { continue }
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
