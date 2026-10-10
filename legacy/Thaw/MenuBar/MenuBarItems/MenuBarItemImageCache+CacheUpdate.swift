//
//  MenuBarItemImageCache+CacheUpdate.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Collections
import os.lock

extension MenuBarItemImageCache {
    // MARK: Update Cache

    /// Display to capture from while a consumer is visible.
    ///
    /// Prefer the Thaw Bar's screen when it is presented so a cross-display
    /// open does not keep sampling the previous menu bar's icon tint.
    @MainActor
    func preferredCaptureDisplayID(
        appState: AppState,
        override: CGDirectDisplayID? = nil
    ) -> CGDirectDisplayID? {
        if let override {
            return override
        }
        if appState.navigationState.isIceBarPresented,
           let iceBarDisplayID = appState.menuBarManager.iceBarPanel.screen?.displayID
        {
            return iceBarDisplayID
        }
        return appState.itemManager.itemCache.displayID
    }

    /// Updates the cache for the given sections unconditionally.
    ///
    /// - Parameter preferredDisplayID: When set (e.g. the Thaw Bar's screen),
    ///   capture from that display instead of the standing item-cache display.
    @MainActor
    func updateCacheWithoutChecks(
        sections: [MenuBarSection.Name],
        preferredDisplayID: CGDirectDisplayID? = nil
    ) async {
        await withCapturePermit {
            await performCacheUpdateWithoutChecks(
                sections: sections,
                preferredDisplayID: preferredDisplayID
            )
        }
    }

    /// Runs one capture operation at a time across live and explicit refreshes.
    @MainActor
    func withCapturePermit(_ operation: @MainActor () async -> Void) async {
        do {
            try await captureSemaphore.wait()
        } catch {
            return
        }
        await operation()
        await captureSemaphore.signal()
    }

    @MainActor
    private func performCacheUpdateWithoutChecks(
        sections: [MenuBarSection.Name],
        preferredDisplayID: CGDirectDisplayID? = nil
    ) async {
        guard let appState else {
            MenuBarItemImageCache.diagLog.warning("updateCacheWithoutChecks: appState is nil, aborting")
            return
        }

        let hasScreenRecording = appState.hasPermission(.screenRecording)
        guard hasScreenRecording else {
            MenuBarItemImageCache.diagLog.debug("updateCacheWithoutChecks: no screen recording permission, aborting")
            return
        }

        let resolvedPreferred = preferredCaptureDisplayID(appState: appState, override: preferredDisplayID)
        guard let resolvedScreen = Self.resolveScreen(preferredDisplayID: resolvedPreferred) else {
            MenuBarItemImageCache.diagLog.warning("updateCacheWithoutChecks: no connected screens available, aborting")
            return
        }
        let screen = resolvedScreen.screen
        if resolvedScreen.usedFallback, let resolvedPreferred {
            MenuBarItemImageCache.diagLog.warning(
                "updateCacheWithoutChecks: cached displayID \(resolvedPreferred) is not connected; using displayID \(screen.displayID)"
            )
        }

        let scale = screen.backingScaleFactor
        MenuBarItemImageCache.diagLog.notice("updateCacheWithoutChecks: displayID=\(screen.displayID) backingScaleFactor=\(Double(scale)) hasNotch=\(screen.hasNotch) menuBarHeight=\(Double(screen.getMenuBarHeightEstimate())) sections=\(sections.map(\.logString))")
        var newImages = [MenuBarItemTag: CapturedImage]()

        for section in sections {
            guard !Task.isCancelled else {
                MenuBarItemImageCache.diagLog.debug("updateCacheWithoutChecks: cancelled before capturing \(section.logString)")
                return
            }

            guard !appState.itemManager.itemCache[section].isEmpty else {
                continue
            }

            let sectionImages = await captureImages(
                for: section,
                scale: scale,
                appState: appState
            )

            guard !sectionImages.isEmpty else {
                // Expected for off-screen sections, which refreshImages handles.
                MenuBarItemImageCache.diagLog.debug(
                    "captureImages: no images captured for \(section.logString) (off-screen or transient failure)"
                )
                continue
            }

            newImages.merge(sectionImages) { _, new in new }
        }

        guard !Task.isCancelled else {
            MenuBarItemImageCache.diagLog.debug("updateCacheWithoutChecks: cancelled before applying cache update")
            return
        }

        let allValidTags = Set(
            appState.itemManager.itemCache.managedItems.map(\.tag)
        )
        let displayID = screen.displayID

        await MainActor.run { [newImages, allValidTags, displayID] in
            let beforeCount = images.count

            // Keep images of recently failed tags; their window may have briefly
            // vanished, and dropping them shows empty icons.
            let recentlyFailedTags = failedCapturesLock.withLock { Set($0.keys) }

            // matchesIgnoringWindowID keeps disk-loaded entries, which have no windowID.
            images = images.filter { key, _ in
                if key.isSystemItem {
                    return allValidTags.contains(key) || recentlyFailedTags.contains(key)
                }
                return containsTagMatchingIgnoringWindowID(allValidTags, target: key) ||
                    containsTagMatchingIgnoringWindowID(recentlyFailedTags, target: key)
            }

            _ = validateAndCleanupInvalidEntries(preserving: recentlyFailedTags)

            for tag in newImages.keys {
                updateAccessOrder(for: tag)
            }

            // A monitor reconnect gives items new windowIDs; drop the old duplicates.
            let newKeysSet = Set(newImages.keys)
            let staleKeys = images.keys.filter { oldKey in
                guard !oldKey.isSystemItem, !newKeysSet.contains(oldKey) else {
                    return false
                }
                return containsTagMatchingIgnoringWindowID(newKeysSet, target: oldKey)
            }
            for tag in staleKeys {
                images.removeValue(forKey: tag)
                accessOrder.remove(tag)
            }

            images.merge(newImages) { _, new in new }

            // Never evict live items, or transient churn (e.g. hotplug) thrashes them.
            if images.count > Self.maxCacheSize {
                let protectedTags = allValidTags
                let excessCount = images.count - Self.maxCacheSize
                let tagsToRemove = leastRecentlyUsedTags(
                    count: excessCount,
                    excluding: protectedTags
                )

                for tag in tagsToRemove {
                    images.removeValue(forKey: tag)
                    accessOrder.remove(tag)
                }

                if !tagsToRemove.isEmpty {
                    MenuBarItemImageCache.diagLog.info(
                        "LRU cache eviction: removed \(tagsToRemove.count) least recently used images (\(protectedTags.count) protected)"
                    )
                }
            }

            accessOrder = OrderedSet(accessOrder.lazy.filter { self.images[$0] != nil })

            let afterCount = images.count
            let finalAccessOrderCount = accessOrder.count
            let totalRemoved = beforeCount - afterCount

            if afterCount > 30 || totalRemoved > 0 {
                MenuBarItemImageCache.diagLog.info(
                    "Image cache: \(afterCount) images, LRU order: \(finalAccessOrderCount) entries (removed \(totalRemoved) stale+invalid images)"
                )
            }

            if afterCount != finalAccessOrderCount {
                MenuBarItemImageCache.diagLog.warning(
                    "Cache inconsistency: \(afterCount) cached images vs \(finalAccessOrderCount) LRU entries"
                )
            }

            if !newImages.isEmpty {
                storeImages(for: displayID, capturedTags: newImages.keys)
            }
        }
    }

    func containsTagMatchingIgnoringWindowID(
        _ tags: Set<MenuBarItemTag>,
        target: MenuBarItemTag
    ) -> Bool {
        for tag in tags where tag.matchesIgnoringWindowID(target) {
            return true
        }
        return false
    }

    /// Updates the cache for the given sections, if necessary.
    func updateCache(
        sections: [MenuBarSection.Name],
        skipRecentMoveCheck: Bool = false,
        allowBackgroundCapture: Bool = false,
        nav: NavigationStateSnapshot? = nil
    ) async {
        guard let appState else {
            MenuBarItemImageCache.diagLog.debug("updateCache: appState is nil, skipping")
            return
        }

        let navSnapshot: NavigationStateSnapshot = if let nav {
            nav
        } else {
            await MainActor.run {
                makeNavigationStateSnapshot()
            }
        }

        if !allowBackgroundCapture {
            let hasVisibleConsumer = hasVisibleCaptureConsumer(nav: navSnapshot)

            guard hasVisibleConsumer else {
                // Normal when nothing visible needs icons.
                return
            }
        }

        if !skipRecentMoveCheck {
            guard
                !appState.itemManager.lastMoveOperationOccurred(
                    within: .seconds(1)
                )
            else {
                MenuBarItemImageCache.diagLog.debug(
                    "Skipping item image cache due to recent item movement"
                )
                return
            }

            // Avoids a stale cache between reset passes.
            if appState.itemManager.isResettingLayout {
                MenuBarItemImageCache.diagLog.debug(
                    "Skipping item image cache because layout reset is in progress"
                )
                return
            }
        }

        MenuBarItemImageCache.diagLog.debug("updateCache: proceeding with cache update for \(sections.count) sections (iceBar=\(navSnapshot.isIceBarPresented), search=\(navSnapshot.isSearchPresented), background=\(allowBackgroundCapture))")
        await updateCacheWithoutChecks(sections: sections)
    }

    /// Updates the cache for all sections, if necessary.
    @MainActor
    func updateCache(nav: NavigationStateSnapshot? = nil) async {
        guard let appState else {
            return
        }

        let navSnapshot: NavigationStateSnapshot = if let nav {
            nav
        } else {
            await MainActor.run {
                makeNavigationStateSnapshot()
            }
        }

        var sectionsNeedingDisplay = [MenuBarSection.Name]()

        if navSnapshot.isSettingsPresented || navSnapshot.isSearchPresented {
            sectionsNeedingDisplay = MenuBarSection.Name.allCases
        } else if navSnapshot.isIceBarPresented, let section = appState.menuBarManager.iceBarPanel
            .currentSection
        {
            sectionsNeedingDisplay.append(section)
        }

        await updateCache(
            sections: sectionsNeedingDisplay,
            skipRecentMoveCheck: navSnapshot.isIceBarPresented,
            nav: navSnapshot
        )
    }

    @MainActor
    func clearImages(for section: MenuBarSection.Name) {
        guard let appState else {
            return
        }
        let tags = Set(appState.itemManager.itemCache[section].map(\.tag))
        images = images.filter { !tags.contains($0.key) }
        for tag in tags {
            accessOrder.remove(tag)
        }
        if images.isEmpty {
            lastCaptureDisplayID = nil
        }
    }

    // MARK: Cache Failed

    /// Whether caching failed for the given section.
    @MainActor
    func cacheFailed(for section: MenuBarSection.Name) -> Bool {
        let hasPermission = ScreenCapture.cachedCheckPermissions()
        guard hasPermission else {
            MenuBarItemImageCache.diagLog.debug("cacheFailed(\(section.logString)): no screen recording permission (cachedCheckPermissions=false)")
            return true
        }
        let items = appState?.itemManager.itemCache[section] ?? []
        guard !items.isEmpty else {
            return false
        }
        let keys = Set(images.keys)
        for item in items where keys.contains(item.tag) {
            return false
        }
        MenuBarItemImageCache.diagLog.debug("cacheFailed(\(section.logString)): no cached images found for \(items.count) items in section (total cached images: \(images.count))")
        return true
    }
}
