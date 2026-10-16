//
//  MenuBarItemImageCache+DisplaySnapshots.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

extension MenuBarItemImageCache {
    // MARK: Per-Display Snapshots

    /// Force-recaptures a section for a specific display, including off-screen
    /// (hidden / always-hidden) items via SkyLight.
    ///
    /// For the Thaw Bar opening on another screen: ``updateCacheWithoutChecks``
    /// skips off-screen items, and waiting for live refresh flashes the wrong tint.
    @MainActor
    func recaptureSection(
        _ section: MenuBarSection.Name,
        preferredDisplayID: CGDirectDisplayID
    ) async {
        guard let appState else { return }
        guard let resolvedScreen = Self.resolveScreen(preferredDisplayID: preferredDisplayID) else {
            return
        }
        let screen = resolvedScreen.screen
        let scale = screen.backingScaleFactor
        let items = appState.itemManager.itemCache.managedItems(for: section)
            .filter { !$0.isControlItem }
        guard !items.isEmpty else { return }

        MenuBarItemImageCache.diagLog.notice(
            "recaptureSection: section=\(section.logString) displayID=\(screen.displayID) items=\(items.count)"
        )

        await withCapturePermit {
            if section == .visible {
                await refreshImages(of: items, scale: scale, viaSCK: true)
                lastSCKRefreshAt = ContinuousClock.now
            } else {
                // Shares the live-refresh cadence so opens can't bypass the SkyLight throttle (#759).
                await awaitOffscreenRefreshSlot(for: section)
                await refreshImages(of: items, scale: scale, viaSCK: false)
            }
        }
        guard !Task.isCancelled else { return }
        storeImages(for: screen.displayID, capturedTags: items.map(\.tag))
    }

    /// Waits for, then claims, the live-refresh offscreen slot for `section`.
    @MainActor
    private func awaitOffscreenRefreshSlot(for section: MenuBarSection.Name) async {
        let interval = Duration.seconds(
            MenuBarLiveRefreshPolicy.refreshInterval(
                for: section,
                target: Self.minIconRefreshInterval
            ) ?? MenuBarCaptureService.minAlwaysHiddenInterval
        )
        let now = ContinuousClock.now
        let lastCaptureAt: ContinuousClock.Instant? = switch section {
        case .hidden: lastHiddenRefreshAt
        case .alwaysHidden: lastAlwaysHiddenRefreshAt
        case .visible: nil
        }
        if let lastCaptureAt, now - lastCaptureAt < interval {
            try? await Task.sleep(for: interval - (now - lastCaptureAt))
        }
        let claimedAt = ContinuousClock.now
        switch section {
        case .hidden:
            lastHiddenRefreshAt = claimedAt
        case .alwaysHidden:
            lastAlwaysHiddenRefreshAt = claimedAt
        case .visible:
            break
        }
    }

    /// Restores a warm per-display snapshot for the Thaw Bar, or clears the
    /// section when only another screen's bitmaps are available.
    ///
    /// Call before ordering the panel front so it never paints another screen's icons.
    ///
    /// - Returns: `true` when a background recapture is still needed (cold or
    ///   incomplete warm restore).
    @MainActor
    @discardableResult
    func prepareImagesForDisplay(_ displayID: CGDirectDisplayID, section: MenuBarSection.Name) -> Bool {
        guard let appState else { return true }
        let sectionItems = appState.itemManager.itemCache[section]
        guard !sectionItems.isEmpty else { return false }

        if let stored = imagesByDisplay[displayID], !stored.isEmpty {
            var applied = 0
            var missingTags = [MenuBarItemTag]()
            for item in sectionItems {
                if let image = Self.image(for: item.tag, in: stored) {
                    images[item.tag] = image
                    updateAccessOrder(for: item.tag)
                    applied += 1
                } else {
                    missingTags.append(item.tag)
                }
            }
            // Drop unrestored tags so previous-display bitmaps cannot linger
            // beside a partial warm restore.
            for tag in missingTags {
                images.removeValue(forKey: tag)
                accessOrder.remove(tag)
            }
            if applied > 0 {
                lastCaptureDisplayID = displayID
                MenuBarItemImageCache.diagLog.notice(
                    "prepareImagesForDisplay: restored \(applied)/\(sectionItems.count) icons for display \(displayID)"
                )
                return !missingTags.isEmpty
            }
        }

        if lastCaptureDisplayID != displayID {
            MenuBarItemImageCache.diagLog.notice(
                "prepareImagesForDisplay: no warm cache for display \(displayID); clearing section \(section.logString) to avoid wrong tint"
            )
            clearImages(for: section)
            return true
        }
        return !sectionHasCachedImages(section)
    }

    /// Snapshots the tags a capture just produced for `displayID`.
    ///
    /// Only the captured tags: `images` holds other sections' bitmaps, possibly
    /// from another display. Entries gone from `images` are dropped.
    @MainActor
    func storeImages(
        for displayID: CGDirectDisplayID,
        capturedTags: some Sequence<MenuBarItemTag>
    ) {
        var snapshot = (imagesByDisplay[displayID] ?? [:]).filter { images[$0.key] != nil }
        for tag in capturedTags {
            if let image = Self.image(for: tag, in: images) {
                snapshot[tag] = image
            }
        }
        guard !snapshot.isEmpty else { return }
        imagesByDisplay[displayID] = snapshot
        lastCaptureDisplayID = displayID
        pruneDisconnectedDisplayCaches()
        enforcePerDisplayCacheLimit()
    }

    @MainActor
    private func pruneDisconnectedDisplayCaches() {
        let connected = Set(NSScreen.screens.map(\.displayID))
        imagesByDisplay = imagesByDisplay.filter { connected.contains($0.key) }
    }

    /// Caps total icons retained across per-display snapshots.
    @MainActor
    private func enforcePerDisplayCacheLimit() {
        let total = imagesByDisplay.values.reduce(0) { $0 + $1.count }
        let limit = Self.maxCacheSize * max(imagesByDisplay.count, 1)
        guard total > limit else { return }

        let standing = lastCaptureDisplayID
        let victims = imagesByDisplay.keys.filter { $0 != standing }
        for displayID in victims {
            imagesByDisplay.removeValue(forKey: displayID)
            let remaining = imagesByDisplay.values.reduce(0) { $0 + $1.count }
            if remaining <= limit {
                return
            }
        }

        if var standingImages = standing.flatMap({ imagesByDisplay[$0] }),
           standingImages.count > Self.maxCacheSize
        {
            let keys = Array(standingImages.keys.prefix(standingImages.count - Self.maxCacheSize))
            for key in keys {
                standingImages.removeValue(forKey: key)
            }
            if let standing {
                imagesByDisplay[standing] = standingImages
            }
        }
    }

    /// Prepares icons for `displayID` and reports whether a fresh capture is needed.
    @MainActor
    func prepareImagesForThawBar(
        displayID: CGDirectDisplayID,
        section: MenuBarSection.Name
    ) -> Bool {
        prepareImagesForDisplay(displayID, section: section)
    }

    @MainActor
    private func sectionHasCachedImages(_ section: MenuBarSection.Name) -> Bool {
        guard let appState else { return false }
        let items = appState.itemManager.itemCache[section]
        guard !items.isEmpty else { return true }
        let keys = Set(images.keys)
        return items.contains { keys.contains($0.tag) }
    }
}
