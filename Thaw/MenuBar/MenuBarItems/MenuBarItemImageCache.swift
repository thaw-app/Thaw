//
//  MenuBarItemImageCache.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine

/// Cache for menu bar item images.
final class MenuBarItemImageCache: ObservableObject {
    private static nonisolated let diagLog = DiagLog(category: "MenuBarItemImageCache")
    /// A representation of a captured menu bar item image.
    struct CapturedImage: Hashable {
        /// The base image.
        let cgImage: CGImage

        /// The scale factor of the image at the time of capture.
        let scale: CGFloat

        /// The image's size, applying ``scale``.
        var scaledSize: CGSize {
            CGSize(
                width: CGFloat(cgImage.width) / scale,
                height: CGFloat(cgImage.height) / scale
            )
        }

        /// The base image, converted to an `NSImage` and applying ``scale``.
        var nsImage: NSImage {
            NSImage(cgImage: cgImage, size: scaledSize)
        }

        /// Returns whether two optional captured images have equivalent visual content.
        ///
        /// Uses pointer equality on `CGImage` as a fast path, falling back to
        /// dimension and pixel-data comparison when instances differ.
        static func isVisuallyEqual(_ old: CapturedImage?, _ new: CapturedImage?) -> Bool {
            guard let old, let new else { return old == nil && new == nil }
            if old.cgImage === new.cgImage { return true }
            guard old.scale == new.scale,
                  old.cgImage.width == new.cgImage.width,
                  old.cgImage.height == new.cgImage.height
            else {
                return false
            }
            guard let oldData = old.cgImage.dataProvider?.data,
                  let newData = new.cgImage.dataProvider?.data
            else {
                return false
            }
            return oldData == newData
        }
    }

    /// The cached item images, keyed by their corresponding tags.
    @Published private(set) var images = [MenuBarItemTag: CapturedImage]()

    /// Maximum number of images to cache to prevent memory growth
    private static let maxCacheSize = 200

    /// LRU tracking: maps each tag to a monotonic counter value.
    /// Lower values are least recently used. O(1) update vs O(n) array removal.
    private var accessTimestamps: [MenuBarItemTag: UInt64] = [:]

    /// Monotonic counter incremented on each access, used for LRU ordering.
    private var accessCounter: UInt64 = 0

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    private var memoryPressureSource: DispatchSourceMemoryPressure?

    /// The currently running cache update task, if any.
    private var currentUpdateTask: Task<Void, Never>?

    deinit {
        memoryPressureSource?.cancel()
        currentUpdateTask?.cancel()
    }

    // MARK: Setup

    /// Sets up the cache.
    @MainActor
    func performSetup(with appState: AppState) {
        self.appState = appState
        MenuBarIconProvider.appState = appState
        configureCancellables()

        // Try to load cached images from disk
        loadFromDisk()
    }

    // MARK: Disk Persistence

    /// Path to the cache file in Caches directory.
    private static var cacheFileURL: URL? {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return cacheDir?.appendingPathComponent("com.stonerl.thaw/imageCache.json")
    }

    /// Maximum age of disk cache before it's considered stale (30 seconds).
    private static let maxCacheAgeSeconds: TimeInterval = 30

    /// Saves the image cache to disk for faster restart.
    func saveToDisk() {
        guard !images.isEmpty else { return }

        guard let url = Self.cacheFileURL else { return }

        let snapshot = images

        Task.detached(priority: .background) {
            let cacheData = snapshot.compactMap { tag, image -> (String, Data)? in
                let nsImage = NSImage(cgImage: image.cgImage, size: image.scaledSize)
                guard let tiffData = nsImage.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmap.representation(using: .png, properties: [:])
                else { return nil }

                let tagString = "\(tag.namespace):\(tag.title)"
                return (tagString, pngData)
            }

            guard cacheData.count == snapshot.count else { return }

            do {
                let directoryURL = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

                let json: [String: Any] = [
                    "timestamp": Date().timeIntervalSince1970,
                    "images": Dictionary(uniqueKeysWithValues: cacheData.map { ($0.0, $0.1.base64EncodedString()) }),
                ]
                let jsonData = try JSONSerialization.data(withJSONObject: json, options: [])
                try jsonData.write(to: url)

                MenuBarItemImageCache.diagLog.debug("Saved \(cacheData.count) images to disk cache")
            } catch {
                MenuBarItemImageCache.diagLog.error("Failed to save image cache to disk: \(error)")
            }
        }
    }

    /// Loads cached images from disk.
    @MainActor
    private func loadFromDisk() {
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

                // Check if cache is stale (older than 30 seconds)
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

                    let parts = tagString.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2 else { continue }

                    let namespace = String(parts[0])
                    let title = String(parts[1])
                    let tag = MenuBarItemTag(namespace: .string(namespace), title: title, windowID: nil)

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

    /// Configures the internal observers for the cache.
    @MainActor
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState {
            // Monitor system memory pressure
            memoryPressureSource?.cancel()
            let source = DispatchSource.makeMemoryPressureSource(
                eventMask: [.warning, .critical],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                self?.handleMemoryPressure()
            }
            source.resume()
            memoryPressureSource = source

            let spaceChangePublisher: AnyPublisher<Void, Never> = NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.activeSpaceDidChangeNotification
            )
            .map { _ in () }
            .eraseToAnyPublisher()

            let screenChangePublisher: AnyPublisher<Void, Never> = NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification
            )
            .map { _ in () }
            .eraseToAnyPublisher()

            let colorChangePublisher: AnyPublisher<Void, Never> = appState.menuBarManager.$averageColorInfo
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher()

            let itemCacheChangePublisher: AnyPublisher<Void, Never> = appState.itemManager.$itemCache
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher()

            Publishers.MergeMany([
                spaceChangePublisher,
                screenChangePublisher,
                colorChangePublisher,
                itemCacheChangePublisher,
            ])
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                self.currentUpdateTask?.cancel()
                self.currentUpdateTask = Task {
                    await self.updateCache()
                }
            }
            .store(in: &c)
        }

        cancellables = c
    }

    /// Handles memory pressure events
    private func handleMemoryPressure() {
        // Clear half the cache on memory warning
        if !images.isEmpty {
            let targetSize = images.count / 2
            let removeCount = images.count - targetSize
            let tagsToRemove = leastRecentlyUsedTags(count: removeCount)

            for tag in tagsToRemove {
                images.removeValue(forKey: tag)
                accessTimestamps.removeValue(forKey: tag)
            }
            MenuBarItemImageCache.diagLog.info(
                "Memory pressure: Cleared \(tagsToRemove.count) items from cache"
            )
        }
    }

    /// Returns the `count` least recently used tags, sorted by access time (oldest first).
    private func leastRecentlyUsedTags(
        count: Int,
        excluding excludedTags: Set<MenuBarItemTag> = []
    ) -> [MenuBarItemTag] {
        let candidates: [(tag: MenuBarItemTag, timestamp: UInt64)]
        if excludedTags.isEmpty {
            candidates = images.keys.map { ($0, accessTimestamps[$0] ?? 0) }
        } else {
            candidates = images.keys
                .filter { !excludedTags.contains($0) }
                .map { ($0, accessTimestamps[$0] ?? 0) }
        }
        return candidates
            .sorted { $0.timestamp < $1.timestamp }
            .prefix(count)
            .map(\.tag)
    }

    // MARK: Cache Access

    /// Updates the access order for a given tag to mark it as most recently used.
    private func updateAccessOrder(for tag: MenuBarItemTag) {
        accessCounter += 1
        accessTimestamps[tag] = accessCounter
    }

    /// Gets an image from the cache and updates its access order.
    ///
    /// For non-system items, falls back to a namespace+title match if the
    /// exact tag (including windowID) is not found. This handles disk-loaded
    /// entries where the windowID is unavailable.
    func image(for tag: MenuBarItemTag) -> CapturedImage? {
        if let image = images[tag] {
            updateAccessOrder(for: tag)
            return image
        }
        // Fallback: match by namespace and title only (ignoring windowID).
        // This covers disk-loaded entries that were stored without a windowID.
        if !tag.isSystemItem,
           let entry = images.first(where: { $0.key.matchesIgnoringWindowID(tag) })
        {
            updateAccessOrder(for: entry.key)
            return entry.value
        }
        return nil
    }

    /// Returns the current cache size for monitoring purposes.
    var cacheSize: Int {
        images.count
    }

    /// Returns the number of tracked LRU entries for debugging.
    var lruEntryCount: Int {
        accessTimestamps.count
    }

    /// Validates cache entries and removes items with invalid window IDs.
    /// Tags in `preserving` are kept even if they are no longer in the item cache.
    /// Returns the number of items removed during cleanup.
    @MainActor
    private func validateAndCleanupInvalidEntries(
        preserving preservedTags: Set<MenuBarItemTag> = []
    ) -> Int {
        guard let appState else { return 0 }

        var removedCount = 0
        let allValidTags = Set(
            appState.itemManager.itemCache.managedItems.map(\.tag)
        )

        // Remove cache entries for items that don't exist in the item cache
        // or have invalid/missing window information, but keep entries that
        // are explicitly preserved (e.g. items with recent capture failures
        // whose cached image should be retained).
        // Use matchesIgnoringWindowID for non-system items so disk-loaded
        // entries (which have no windowID) are not incorrectly evicted.
        let invalidTags = images.keys.filter { tag in
            let isValid = if tag.isSystemItem {
                allValidTags.contains(tag)
            } else {
                allValidTags.contains(where: { $0.matchesIgnoringWindowID(tag) })
            }
            let isPreserved = if tag.isSystemItem {
                preservedTags.contains(tag)
            } else {
                preservedTags.contains(where: { $0.matchesIgnoringWindowID(tag) })
            }
            return !isValid && !isPreserved
        }

        for invalidTag in invalidTags {
            images.removeValue(forKey: invalidTag)
            accessTimestamps.removeValue(forKey: invalidTag)
            removedCount += 1
        }

        if removedCount > 0 {
            MenuBarItemImageCache.diagLog.info(
                "Cache cleanup: removed \(removedCount) invalid entries with missing window information"
            )
        }

        return removedCount
    }

    /// Manually triggers cleanup of invalid cache entries.
    /// This can be called when you suspect memory issues with orphaned entries.
    @MainActor
    func performCacheCleanup() {
        let removedCount = validateAndCleanupInvalidEntries()
        MenuBarItemImageCache.diagLog.info(
            "Manual cache cleanup completed: removed \(removedCount) invalid entries"
        )
    }

    /// Logs detailed cache information for debugging memory issues.
    /// This method is NOT called automatically - you must call it explicitly.
    func logCacheStatus(_ context: String = "Manual check") {
        let imageSize = images.count
        let lruSize = accessTimestamps.count
        let maxSize = Self.maxCacheSize
        let usagePercent = (imageSize * 100) / maxSize

        let lruSorted = accessTimestamps.sorted { $0.value < $1.value }
        let lruDescription = lruSorted.map { "\($0.key)" }.joined(separator: ", ")

        MenuBarItemImageCache.diagLog.info(
            """
            === Image Cache Status: \(context) ===
            Cache size: \(imageSize)/\(maxSize) (\(usagePercent)% full)
            LRU order count: \(lruSize)
            Memory impact: ~\(imageSize * 100)KB (estimated)
            LRU order: \(lruDescription)
            ======================================
            """
        )
    }

    // MARK: Update Cache

    /// Updates the cache for the given sections, without checking whether
    /// caching is necessary.
    func updateCacheWithoutChecks(sections: [MenuBarSection.Name]) async {
        guard let appState else {
            MenuBarItemImageCache.diagLog.warning("updateCacheWithoutChecks: appState is nil, aborting")
            return
        }

        guard let displayID = await appState.itemManager.itemCache.displayID else {
            MenuBarItemImageCache.diagLog.warning("updateCacheWithoutChecks: itemCache.displayID is nil, aborting")
            return
        }

        guard let screen = NSScreen.screens.first(where: {
            $0.displayID == displayID
        }) else {
            MenuBarItemImageCache.diagLog.warning("updateCacheWithoutChecks: no screen found for displayID \(displayID)")
            return
        }

        let scale = screen.backingScaleFactor
        var newImages = [MenuBarItemTag: CapturedImage]()

        for section in sections {
            guard !Task.isCancelled else {
                MenuBarItemImageCache.diagLog.debug("updateCacheWithoutChecks: cancelled before capturing \(section.logString)")
                return
            }

            guard await !appState.itemManager.itemCache[section].isEmpty else {
                continue
            }

            // Resolve icons from asset catalogs and SF Symbols first.
            // This works without screen capture permissions.
            let sectionItems = await appState.itemManager.itemCache.managedItems(for: section)
            var catalogCount = 0
            for item in sectionItems {
                if let catalogIcon = await MenuBarIconProvider.icon(for: item, scale: scale) {
                    newImages[item.tag] = catalogIcon
                    catalogCount += 1
                }
            }
            if catalogCount > 0 {
                MenuBarItemImageCache.diagLog.debug(
                    "Asset catalog: resolved \(catalogCount) icon(s) for \(section.logString)"
                )
            }
        }

        guard !Task.isCancelled else {
            MenuBarItemImageCache.diagLog.debug("updateCacheWithoutChecks: cancelled before applying cache update")
            return
        }

        // Get the set of valid item tags from all sections to clean up stale entries
        let allValidTags = await Set(
            appState.itemManager.itemCache.managedItems.map(\.tag)
        )

        await MainActor.run { [newImages, allValidTags] in
            let beforeCount = images.count

            // Remove images for items that no longer exist in the item cache.
            // Use matchesIgnoringWindowID for non-system items so disk-loaded
            // entries are not incorrectly evicted when their windowID is nil.
            images = images.filter { key, _ in
                if key.isSystemItem {
                    return allValidTags.contains(key)
                }
                return allValidTags.contains(where: { $0.matchesIgnoringWindowID(key) })
            }

            _ = validateAndCleanupInvalidEntries()

            // Mark all newly captured images as most recently used
            for tag in newImages.keys {
                self.updateAccessOrder(for: tag)
            }

            // Merge in the new images
            images.merge(newImages) { _, new in new }

            // Enforce cache size limit using LRU eviction, but never evict
            // items that belong to the sections we just captured (i.e. the
            // sections currently being displayed).
            if images.count > Self.maxCacheSize {
                let protectedTags = Set(newImages.keys)
                let excessCount = images.count - Self.maxCacheSize
                let tagsToRemove = leastRecentlyUsedTags(
                    count: excessCount,
                    excluding: protectedTags
                )

                for tag in tagsToRemove {
                    images.removeValue(forKey: tag)
                    accessTimestamps.removeValue(forKey: tag)
                }

                if !tagsToRemove.isEmpty {
                    MenuBarItemImageCache.diagLog.info(
                        "LRU cache eviction: removed \(tagsToRemove.count) least recently used images (\(protectedTags.count) protected)"
                    )
                }
            }

            // Remove stale timestamps for images that no longer exist
            accessTimestamps = accessTimestamps.filter { images.keys.contains($0.key) }

            let afterCount = images.count
            let finalAccessOrderCount = accessTimestamps.count
            let totalRemoved = beforeCount - afterCount

            // Log cache status for monitoring (verbose only when needed)
            if afterCount > 30 || totalRemoved > 0 {
                MenuBarItemImageCache.diagLog.info(
                    "Image cache: \(afterCount) images, LRU order: \(finalAccessOrderCount) entries (removed \(totalRemoved) stale+invalid images)"
                )
            }

            // Warning if cache and access order are out of sync
            if afterCount != finalAccessOrderCount {
                MenuBarItemImageCache.diagLog.warning(
                    "Cache inconsistency: \(afterCount) cached images vs \(finalAccessOrderCount) LRU entries"
                )
            }
        }
    }

    /// Updates the cache for the given sections, if necessary.
    func updateCache(sections: [MenuBarSection.Name], skipRecentMoveCheck: Bool = false) async {
        guard let appState else {
            MenuBarItemImageCache.diagLog.debug("updateCache: appState is nil, skipping")
            return
        }

        let isIceBarPresented = await appState.navigationState.isIceBarPresented
        let isSearchPresented = await appState.navigationState.isSearchPresented

        if !isIceBarPresented, !isSearchPresented {
            let isAppFrontmost = await appState.navigationState.isAppFrontmost
            let isSettingsPresented = await appState.navigationState.isSettingsPresented
            let settingsNavID = await appState.navigationState.settingsNavigationIdentifier

            guard isAppFrontmost, isSettingsPresented, settingsNavID == .menuBarLayout else {
                // This is the normal path when IceBar/search/settings are not visible — not an error
                return
            }
        }

        if !skipRecentMoveCheck {
            guard
                await !appState.itemManager.lastMoveOperationOccurred(
                    within: .seconds(1)
                )
            else {
                MenuBarItemImageCache.diagLog.debug(
                    "Skipping item image cache due to recent item movement"
                )
                return
            }

            // Skip updates during layout reset to prevent stale cache between passes
            if await appState.itemManager.isResettingLayout {
                MenuBarItemImageCache.diagLog.debug(
                    "Skipping item image cache because layout reset is in progress"
                )
                return
            }
        }

        MenuBarItemImageCache.diagLog.debug("updateCache: proceeding with cache update for \(sections.count) sections (iceBar=\(isIceBarPresented), search=\(isSearchPresented))")
        await updateCacheWithoutChecks(sections: sections)
    }

    /// Updates the cache for all sections, if necessary.
    func updateCache() async {
        guard let appState else {
            return
        }

        let isIceBarPresented = await appState.navigationState.isIceBarPresented
        let isSearchPresented = await appState.navigationState.isSearchPresented
        let isSettingsPresented = await appState.navigationState
            .isSettingsPresented

        var sectionsNeedingDisplay = [MenuBarSection.Name]()

        if isSettingsPresented || isSearchPresented {
            sectionsNeedingDisplay = MenuBarSection.Name.allCases
        } else if isIceBarPresented, let section = await appState.menuBarManager.iceBarPanel
            .currentSection
        {
            sectionsNeedingDisplay.append(section)
        }

        await updateCache(
            sections: sectionsNeedingDisplay,
            skipRecentMoveCheck: isIceBarPresented
        )
    }

    /// Clears the images for the given section.
    @MainActor
    func clearImages(for section: MenuBarSection.Name) {
        guard let appState else {
            return
        }
        let tags = Set(appState.itemManager.itemCache[section].map(\.tag))
        images = images.filter { !tags.contains($0.key) }
        for tag in tags {
            accessTimestamps.removeValue(forKey: tag)
        }
    }

    /// Clears all cached images.
    @MainActor
    func clearAll() {
        images.removeAll()
        accessTimestamps.removeAll()
        accessCounter = 0
    }

    // MARK: Cache Failed

    /// Returns a Boolean value that indicates whether caching menu bar items
    /// failed for the given section.
    @MainActor
    func cacheFailed(for section: MenuBarSection.Name) -> Bool {
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
