//
//  MenuBarItemManager+CachePublication.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

extension MenuBarItemManager {
    /// What a complete scan does once the cache it read is published: the saved-order mirror, unseen
    /// hosts and overflow balancing, none of which a partial scan may do.
    func finishPublishedCache(_ context: CacheContext, running: RunningApplicationSnapshot) {
        publishedCacheAwaitsFullScan = false

        // Reset isRestoringItemOrder if it's been stuck for too long (10 seconds).
        // This prevents stale flags from blocking saves after user manual moves.
        if isRestoringItemOrder, let timestamp = isRestoringItemOrderTimestamp, timestamp.duration(to: .now) > .seconds(10) {
            MenuBarItemManager.diagLog.debug("Resetting stale isRestoringItemOrder flag (timeout)")
            isRestoringItemOrder = false
            isRestoringItemOrderTimestamp = nil
        }

        mirrorSavedSectionOrderIfSettled(from: context.cache, controlItems: context.controlItems)
        noteUnseenMenuBarHosts(in: context.cache, running: running)

        MenuBarItemManager.diagLog.debug("Updated menu bar item cache: visible=\(context.cache[.visible].count), hidden=\(context.cache[.hidden].count), alwaysHidden=\(context.cache[.alwaysHidden].count)")

        // Rebalance external item floods here; coalesce tasks so assertion reflow cannot trigger rebalance thrashing.
        if configuration.enableMenuBarItemOverflow == true {
            scheduleOverflowRebalance(cause: .cachePublished, reason: .externalChange)
        }
    }

    /// Whether a complete scan that finds the published cache unchanged still owes the work a partial scan left it.
    static nonisolated func unchangedCacheOwesDeferredWork(observationOnly: Bool, awaitsFullScan: Bool) -> Bool {
        !observationOnly && awaitsFullScan
    }
}
