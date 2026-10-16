//
//  MenuBarItemImageCache+Storage.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
import Cocoa
import Collections
import os.lock

extension MenuBarItemImageCache {
    // MARK: Cache Access

    func updateAccessOrder(for tag: MenuBarItemTag) {
        if accessOrder.contains(tag) {
            accessOrder.move(members: CollectionOfOne(tag), to: accessOrder.endIndex)
        } else {
            accessOrder.append(tag)
        }
    }

    /// Gets an image from the cache and updates its access order.
    ///
    /// Non-system items fall back to a namespace+title match, since disk-loaded
    /// entries have no windowID.
    func image(for tag: MenuBarItemTag) -> CapturedImage? {
        guard let image = Self.image(for: tag, in: images) else {
            return nil
        }
        // Prefer the exact key when present so access-order tracks the live tag.
        if images[tag] != nil {
            updateAccessOrder(for: tag)
        } else if let matched = images.keys.first(where: { $0.matchesIgnoringWindowID(tag) }) {
            updateAccessOrder(for: matched)
        }
        return image
    }

    /// Looks up `tag` in `store`, with the same exact-then-`matchesIgnoringWindowID`
    /// fallback used by ``image(for:)``.
    static func image(
        for tag: MenuBarItemTag,
        in store: [MenuBarItemTag: CapturedImage]
    ) -> CapturedImage? {
        if let image = store[tag] {
            return image
        }
        guard !tag.isSystemItem else { return nil }
        return store.first(where: { $0.key.matchesIgnoringWindowID(tag) })?.value
    }

    /// Returns the item's image with its transparent left and right margins
    /// trimmed off, ready to display at its captured scale.
    ///
    /// Memoized per source CGImage: SwiftUI bodies call this for every row on
    /// every keystroke.
    func trimmedImage(for tag: MenuBarItemTag) -> NSImage? {
        guard let captured = image(for: tag) else {
            trimmedImages.removeValue(forKey: tag)
            return nil
        }
        if let memo = trimmedImages[tag], memo.source === captured.cgImage {
            return memo.image
        }
        guard let trimmed = captured.cgImage.trimmingTransparency(around: [.minXEdge, .maxXEdge]) else {
            return nil
        }
        let image = NSImage(
            cgImage: trimmed,
            size: CGSize(
                width: CGFloat(trimmed.width) / captured.scale,
                height: CGFloat(trimmed.height) / captured.scale
            )
        )
        // Entries are only ever added here, so drop the ones whose images have
        // since left the cache rather than pruning at all 15 mutation sites.
        if trimmedImages.count > images.count {
            trimmedImages = trimmedImages.filter { images[$0.key] != nil }
        }
        trimmedImages[tag] = (captured.cgImage, image)
        return image
    }

    var cacheSize: Int {
        images.count
    }

    var lruEntryCount: Int {
        accessOrder.count
    }

    /// Removes entries with invalid window IDs, except tags in `preserving`.
    /// Returns the number removed.
    @MainActor
    func validateAndCleanupInvalidEntries(
        preserving preservedTags: Set<MenuBarItemTag> = []
    ) -> Int {
        guard let appState else { return 0 }

        var removedCount = 0
        let allValidTags = Set(
            appState.itemManager.itemCache.managedItems.map(\.tag)
        )

        // matchesIgnoringWindowID keeps disk-loaded entries, which have no windowID.
        let invalidTags = images.keys.filter { tag in
            let isValid = if tag.isSystemItem {
                allValidTags.contains(tag)
            } else {
                containsTagMatchingIgnoringWindowID(allValidTags, target: tag)
            }
            let isPreserved = if tag.isSystemItem {
                preservedTags.contains(tag)
            } else {
                containsTagMatchingIgnoringWindowID(preservedTags, target: tag)
            }
            return !isValid && !isPreserved
        }

        for invalidTag in invalidTags {
            images.removeValue(forKey: invalidTag)
            accessOrder.remove(invalidTag)
            removedCount += 1
        }

        if removedCount > 0 {
            MenuBarItemImageCache.diagLog.info(
                "Cache cleanup: removed \(removedCount) invalid entries with missing window information"
            )
        }

        return removedCount
    }

    /// Manually cleans up invalid entries.
    @MainActor
    func performCacheCleanup() {
        let removedCount = validateAndCleanupInvalidEntries()
        let failedCleared = failedCapturesLock.withLock { dict in
            let count = dict.count
            dict.removeAll()
            return count
        }
        MenuBarItemImageCache.diagLog.info(
            "Manual cache cleanup completed: removed \(removedCount) invalid entries, cleared \(failedCleared) failed captures"
        )
    }

    /// Logs cache details for debugging memory issues. Never called automatically.
    func logCacheStatus(_ context: String = "Manual check") {
        let imageSize = images.count
        let lruSize = accessOrder.count
        let maxSize = Self.maxCacheSize
        let usagePercent = (imageSize * 100) / maxSize
        let (failedCount, blacklistedCount) = failedCapturesLock.withLock { dict in
            (dict.count, dict.values.count(where: { $0.failureCount >= Self.maxFailuresBeforeBlacklist }))
        }

        let lruDescription = accessOrder.map { "\($0)" }.joined(separator: ", ")

        MenuBarItemImageCache.diagLog.info(
            """
            === Image Cache Status: \(context) ===
            Cache size: \(imageSize)/\(maxSize) (\(usagePercent)% full)
            LRU order count: \(lruSize)
            Failed captures: \(failedCount) (blacklisted: \(blacklistedCount))
            Memory impact: ~\(imageSize * 100)KB (estimated)
            LRU order: \(lruDescription)
            ======================================
            """
        )
    }

    @MainActor
    func clearAll() {
        images.removeAll()
        accessOrder.removeAll()
        imagesByDisplay.removeAll()
        lastCaptureDisplayID = nil
        failedCapturesLock.withLock { $0.removeAll() }
    }

    // MARK: Memory Pressure

    func handleMemoryPressure() {
        if !images.isEmpty {
            let targetSize = images.count / 2
            let removeCount = images.count - targetSize
            let tagsToRemove = leastRecentlyUsedTags(count: removeCount)

            for tag in tagsToRemove {
                images.removeValue(forKey: tag)
                accessOrder.remove(tag)
            }
            MenuBarItemImageCache.diagLog.info(
                "Memory pressure: Cleared \(tagsToRemove.count) items from cache"
            )
        }

        // Per-display warm snapshots are independent of the standing LRU; drop
        // non-standing displays first, then trim the standing copy to match.
        let standing = lastCaptureDisplayID
        for displayID in imagesByDisplay.keys where displayID != standing {
            imagesByDisplay.removeValue(forKey: displayID)
        }
        if let standing, var standingImages = imagesByDisplay[standing] {
            standingImages = standingImages.filter { images[$0.key] != nil }
            if standingImages.count > images.count {
                let excess = standingImages.count - images.count
                let dropKeys = Array(standingImages.keys.prefix(excess))
                for key in dropKeys {
                    standingImages.removeValue(forKey: key)
                }
            }
            imagesByDisplay[standing] = standingImages
        }
    }

    /// Returns the count least recently used tags, sorted by access time (oldest first).
    func leastRecentlyUsedTags(
        count: Int,
        excluding excludedTags: Set<MenuBarItemTag> = []
    ) -> [MenuBarItemTag] {
        var candidates = images.keys.filter {
            !accessOrder.contains($0) && !excludedTags.contains($0)
        }
        candidates.append(contentsOf: accessOrder.lazy.filter {
            self.images[$0] != nil && !excludedTags.contains($0)
        })
        return Array(candidates.prefix(count))
    }

    // MARK: Disk Persistence

    private static var cacheFileURL: URL? {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return cacheDir?.appendingPathComponent("com.stonerl.thaw/imageCache.json")
    }

    private static nonisolated let maxCacheAgeSeconds: TimeInterval = 30

    func saveToDisk() {
        guard !images.isEmpty else { return }

        guard let url = Self.cacheFileURL else { return }

        let snapshot = images

        Task.detached(priority: .background) {
            let cacheData = snapshot.map { tag, image -> (String, Data)? in
                let nsImage = NSImage(cgImage: image.cgImage, size: image.scaledSize)
                guard let tiffData = nsImage.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmap.representation(using: .png, properties: [:])
                else { return nil }

                let tagString = tag.persistenceKey
                return (tagString, pngData)
            }.compacted()

            guard cacheData.count == snapshot.count else { return }

            do {
                let directoryURL = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

                let json: [String: Any] = [
                    "timestamp": Date().timeIntervalSince1970,
                    "images": Dictionary(
                        cacheData.map { ($0.0, $0.1.base64EncodedString()) },
                        uniquingKeysWith: { _, new in new }
                    ),
                ]
                let jsonData = try JSONSerialization.data(withJSONObject: json, options: [])
                try jsonData.write(to: url)

                MenuBarItemImageCache.diagLog.debug("Saved \(cacheData.count) images to disk cache")
            } catch {
                MenuBarItemImageCache.diagLog.error("Failed to save image cache to disk: \(error)")
            }
        }
    }

    @MainActor
    func loadFromDisk() {
        guard let url = Self.cacheFileURL,
              FileManager.default.fileExists(atPath: url.path)
        else { return }

        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }

            do {
                let jsonData = try Data(contentsOf: url)
                guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let timestamp = json["timestamp"] as? TimeInterval,
                      let imagesDict = json["images"] as? [String: String] else { return }

                let cacheAge = Date().timeIntervalSince1970 - timestamp
                if cacheAge > Self.maxCacheAgeSeconds {
                    MenuBarItemImageCache.diagLog.debug("Disk cache is \(Int(cacheAge))s old, deleting stale cache")
                    try? FileManager.default.removeItem(at: url)
                    return
                }

                var loadedImages = [MenuBarItemTag: CapturedImage]()

                for (tagString, base64) in imagesDict {
                    guard let data = Data(base64Encoded: base64),
                          let image = NSImage(data: data),
                          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    else { continue }

                    guard let tag = MenuBarItemTag(persistenceKey: tagString) else { continue }

                    let captured = CapturedImage(cgImage: cgImage, scale: image.size.width > 0 ? CGFloat(cgImage.width) / image.size.width : 1.0)
                    loadedImages[tag] = captured
                }

                if !loadedImages.isEmpty {
                    let imagesToLoad = loadedImages
                    let loadedCount = loadedImages.count
                    await MainActor.run {
                        for (tag, image) in imagesToLoad {
                            self.images[tag] = image
                            self.updateAccessOrder(for: tag)
                        }
                        MenuBarItemImageCache.diagLog.debug("Loaded \(loadedCount) images from disk cache (\(Int(cacheAge))s old)")
                    }
                }
            } catch {
                MenuBarItemImageCache.diagLog.error("Failed to load image cache from disk: \(error)")
            }
        }
    }
}
