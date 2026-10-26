//
//  MenuBarDisplayChangeEffects.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

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
        // After a disconnect a stale Control Center edge gives a negative overflow budget that saves hidden items as visible, so the restore waits for settled geometry.
        itemManager.startSettlingPeriod(reason: reason)
    }

    func awaitSettle() async {
        await SettlingWait.follow(
            isSettling: { itemManager.isInStartupSettling },
            currentTask: { itemManager.startupSettlingTask }
        )
    }

    /// The settle already re-read the item cache, so items carry their current displays; another full
    /// read would cost seconds with many apps.
    func cleanImagesAfterRemoval() async {
        imageCache.performCacheCleanup()
        await imageCache.recaptureNow(sections: MenuBarSection.Name.allCases)
    }
}
