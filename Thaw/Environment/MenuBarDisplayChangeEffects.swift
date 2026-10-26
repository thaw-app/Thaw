//
//  MenuBarDisplayChangeEffects.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// The display-change steps as the item manager, the repair orchestrator and the image cache carry them out.
@MainActor
final class MenuBarDisplayChangeEffects: DisplayChangeEffects {
    private let itemManager: MenuBarItemManager
    private let repairs: RepairOrchestrator
    private let imageCache: MenuBarItemImageCache

    init(itemManager: MenuBarItemManager, repairs: RepairOrchestrator, imageCache: MenuBarItemImageCache) {
        self.itemManager = itemManager
        self.repairs = repairs
        self.imageCache = imageCache
    }

    func stampDisplayChanged() {
        repairs.interruptAutomaticWork(by: .displayChanged)
    }

    func startSettle(reason: String) {
        // Defer saved-layout restore until the geometry settles; after a disconnect a stale Control Center edge yields a negative overflow budget and persists hidden items as visible.
        itemManager.startSettlingPeriod(reason: reason)
    }

    /// Waits for the settling task, following it when a later settle replaces it. A cancelled run stops waiting.
    func awaitSettle() async {
        while !Task.isCancelled, itemManager.isInStartupSettling, let task = itemManager.startupSettlingTask {
            await task.value
            guard itemManager.startupSettlingTask != task else { return }
        }
    }

    /// The settle polls the item cache from its start and its tail reads it twice more, so items already carry their
    /// current displays here; another full read would only cost seconds with many apps.
    func refreshCaches(cleansImages: Bool) async {
        guard cleansImages else { return }
        // Drop images of items no longer present and recapture for the remaining display.
        imageCache.performCacheCleanup()
        await imageCache.recaptureNow(sections: MenuBarSection.Name.allCases)
    }
}
