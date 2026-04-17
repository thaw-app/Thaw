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

    /// The result of an image capture operation.
    private struct CaptureResult {
        /// The successfully captured images.
        var images = [MenuBarItemTag: CapturedImage]()

        /// The menu bar items excluded from the capture.
        var excluded = [MenuBarItem]()
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

    /// Failed capture tracking to skip repeatedly failing items
    private struct FailedCapture: Hashable {
        let tag: MenuBarItemTag
        let failureCount: Int
        let lastFailureTime: Date
    }

    private var failedCaptures: [MenuBarItemTag: FailedCapture] = [:]

    /// Configuration for failed capture handling
    private static let maxFailuresBeforeBlacklist = 3
    private static let blacklistCooldownSeconds: TimeInterval = 30 // 30 seconds

    /// Queue to run cache operations.
    private let queue = DispatchQueue(
        label: "MenuBarItemImageCache",
        qos: .background
    )

    /// Image capture options.
    private let captureOption: CGWindowImageOption = [
        .boundsIgnoreFraming, .bestResolution,
    ]

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    private var memoryPressureSource: DispatchSourceMemoryPressure?

    /// The currently running cache update task, if any.
    private var currentUpdateTask: Task<Void, Never>?

    /// The currently running live-refresh task, if any.
    private var liveRefreshTask: Task<Void, Never>?

    deinit {
        memoryPressureSource?.cancel()
        currentUpdateTask?.cancel()
        liveRefreshTask?.cancel()
    }

    // MARK: Setup

    /// Sets up the cache.
    @MainActor
    func performSetup(with appState: AppState) {
        self.appState = appState
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
            let cacheData = snapshot.map { tag, image -> (String, Data)? in
                let nsImage = NSImage(cgImage: image.cgImage, size: image.scaledSize)
                guard let tiffData = nsImage.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmap.representation(using: .png, properties: [:])
                else { return nil }

                let tagString = "\(tag.namespace):\(tag.title)"
                return (tagString, pngData)
            }.compactMap { $0 }

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

            // Observe navigation state changes to start/stop live refresh
            Publishers.CombineLatest4(
                appState.navigationState.$isIceBarPresented,
                appState.navigationState.$isSearchPresented,
                appState.navigationState.$isSettingsPresented,
                appState.navigationState.$settingsNavigationIdentifier
            )
            .combineLatest(appState.navigationState.$isAppFrontmost)
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.startLiveRefreshIfNeeded()
            }
            .store(in: &c)

            // Restart the live refresh loop when the icon refresh interval changes
            appState.settings.advanced.$iconRefreshInterval
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self, self.liveRefreshTask != nil else { return }
                    self.liveRefreshTask?.cancel()
                    self.liveRefreshTask = nil
                    self.startLiveRefreshIfNeeded()
                }
                .store(in: &c)
        }

        cancellables = c
    }

    // MARK: Live Refresh

    /// Starts or stops the live image refresh loop based on navigation state.
    @MainActor
    private func startLiveRefreshIfNeeded() {
        guard let appState else {
            liveRefreshTask?.cancel()
            liveRefreshTask = nil
            return
        }

        let nav = appState.navigationState
        let needsRefresh = nav.isIceBarPresented
            || nav.isSearchPresented
            || (nav.isAppFrontmost && nav.isSettingsPresented
                && nav.settingsNavigationIdentifier == .menuBarLayout)

        if needsRefresh {
            // Already running — don't restart
            guard liveRefreshTask == nil else { return }
            MenuBarItemImageCache.diagLog.debug(
                "Starting live refresh (iceBar=\(nav.isIceBarPresented), search=\(nav.isSearchPresented), settings=\(nav.isSettingsPresented))"
            )
            liveRefreshTask = Task { [weak self, weak appState] in
                guard let self, let appState else { return }
                await self.runLiveRefreshLoop(appState: appState)
            }
        } else {
            if liveRefreshTask != nil {
                MenuBarItemImageCache.diagLog.debug("Stopping live refresh")
            }
            liveRefreshTask?.cancel()
            liveRefreshTask = nil
        }
    }

    /// The centralized live refresh loop for image updates.
    ///
    /// Runs a single capture loop that serves all consumer views (IceBar,
    /// Search, Layout Settings) instead of each view running its own loop.
    /// Heavy work (`refreshImages`) is `nonisolated` and runs off the main
    /// actor — only navigation state reads happen on `@MainActor`.
    @MainActor
    private func runLiveRefreshLoop(appState: AppState) async {
        MenuBarItemImageCache.diagLog.debug("Live refresh loop started")

        while !Task.isCancelled {
            let interval = appState.settings.advanced.iconRefreshInterval
            let ms = Int(interval * 1000)
            try? await Task.sleep(for: .milliseconds(ms))
            guard !Task.isCancelled else { break }

            let nav = appState.navigationState

            // Determine display
            let displayID = appState.itemManager.itemCache.displayID
                ?? Bridging.getActiveMenuBarDisplayID()
                ?? CGMainDisplayID()
            guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
                continue
            }

            // Determine which sections to refresh based on what's visible
            let sections: [MenuBarSection.Name]
            if nav.isSearchPresented
                || (nav.isSettingsPresented && nav.settingsNavigationIdentifier == .menuBarLayout)
            {
                sections = MenuBarSection.Name.allCases
            } else if nav.isIceBarPresented,
                      let current = appState.menuBarManager.iceBarPanel.currentSection
            {
                sections = [current]
            } else {
                // No consumer visible on this tick — keep looping so the
                // Combine observer can properly cancel the task. Using
                // `break` here would race with IceBar close() where
                // currentSection is nilled before isIceBarPresented.
                continue
            }

            for section in sections {
                let items = appState.itemManager.itemCache.managedItems(for: section)
                guard !items.isEmpty else { continue }
                await refreshImages(of: items, scale: screen.backingScaleFactor)
            }
        }

        MenuBarItemImageCache.diagLog.debug("Live refresh loop stopped")
    }

    // MARK: Capturing Images

    /// Captures a composite image of the given items, then crops out an image
    /// for each item and returns the result.
    ///
    /// Accepts pre-fetched window bounds alongside each item to avoid a
    /// redundant `getWindowBounds` system call and eliminate the TOCTOU race
    /// where a window could move between bounds lookup and composite capture.
    /// All items passed to this function are expected to be on-screen;
    /// off-screen items should be pre-filtered by the caller.
    private nonisolated func compositeCapture(
        _ itemsWithBounds: [(item: MenuBarItem, bounds: CGRect)],
        scale: CGFloat
    ) -> CaptureResult {
        var result = CaptureResult()

        var windowIDs = [CGWindowID]()
        var storage = [CGWindowID: (MenuBarItem, CGRect)]()
        var boundsUnion = CGRect.null

        for (item, bounds) in itemsWithBounds {
            windowIDs.append(item.windowID)
            storage[item.windowID] = (item, bounds)
            boundsUnion = boundsUnion.union(bounds)
        }

        // Defensive guard: callers pre-filter empty arrays, but this protects
        // against future misuse.
        guard !windowIDs.isEmpty else {
            return result
        }

        let compositeImage = ScreenCapture.captureWindows(
            with: windowIDs,
            option: captureOption
        )

        guard let compositeImage else {
            MenuBarItemImageCache.diagLog.warning("compositeCapture: ScreenCapture.captureWindows returned nil for \(windowIDs.count) windows")
            result.excluded = itemsWithBounds.map(\.item)
            return result
        }

        let expectedWidth = boundsUnion.width * scale
        let actualWidth = CGFloat(compositeImage.width)
        guard actualWidth == expectedWidth else {
            MenuBarItemImageCache.diagLog.warning("compositeCapture: width mismatch — expected \(expectedWidth) (boundsUnion.width=\(boundsUnion.width) * scale=\(scale)) but got \(actualWidth). Image dimensions: \(compositeImage.width)x\(compositeImage.height)")
            result.excluded = itemsWithBounds.map(\.item)
            return result
        }

        guard !compositeImage.isTransparent() else {
            MenuBarItemImageCache.diagLog.warning("compositeCapture: composite image is fully transparent (\(compositeImage.width)x\(compositeImage.height)) — screen recording permission may not be effective")
            result.excluded = itemsWithBounds.map(\.item)
            return result
        }

        MenuBarItemImageCache.diagLog.debug(
            "compositeCapture: composite image OK (\(compositeImage.width)x\(compositeImage.height)), cropping \(windowIDs.count) items"
        )

        // Crop out each item from the composite.
        var cropSuccessCount = 0
        var cropNilCount = 0
        var cropTransparentCount = 0
        for windowID in windowIDs {
            guard let (item, bounds) = storage[windowID] else {
                continue
            }

            // Check if this item should be skipped due to repeated failures
            if shouldSkipCapture(for: item) {
                MenuBarItemImageCache.diagLog.debug(
                    "Skipping composite capture for repeatedly failing item: \(item.logString)"
                )
                result.excluded.append(item)
                continue
            }

            let cropRect = CGRect(
                x: (bounds.origin.x - boundsUnion.origin.x) * scale,
                y: (bounds.origin.y - boundsUnion.origin.y) * scale,
                width: bounds.width * scale,
                height: bounds.height * scale
            )

            let croppedImage = compositeImage.cropping(to: cropRect)
            guard let croppedImage else {
                cropNilCount += 1
                recordCaptureFailure(for: item)
                result.excluded.append(item)
                continue
            }
            guard !croppedImage.isTransparent() else {
                cropTransparentCount += 1
                recordCaptureFailure(for: item)
                result.excluded.append(item)
                continue
            }

            // Record success
            cropSuccessCount += 1
            recordCaptureSuccess(for: item)
            result.images[item.tag] = CapturedImage(
                cgImage: croppedImage,
                scale: scale
            )
        }

        MenuBarItemImageCache.diagLog.debug(
            "compositeCapture: crops done — \(cropSuccessCount) ok, \(cropNilCount) nil, \(cropTransparentCount) transparent"
        )

        return result
    }

    /// Captures an image of each of the given items individually, then
    /// returns the result.
    private nonisolated func individualCapture(
        _ items: [MenuBarItem],
        scale: CGFloat
    ) -> CaptureResult {
        var result = CaptureResult()
        var capturedCount = 0
        var nilImageCount = 0
        var transparentCount = 0
        var skippedCount = 0

        for item in items {
            // Check if this item should be skipped due to repeated failures
            if shouldSkipCapture(for: item) {
                MenuBarItemImageCache.diagLog.debug(
                    "Skipping capture for repeatedly failing item: \(item.logString)"
                )
                skippedCount += 1
                result.excluded.append(item)
                continue
            }

            let image = ScreenCapture.captureWindow(
                with: item.windowID,
                option: captureOption
            )

            guard let image else {
                MenuBarItemImageCache.diagLog.debug("individualCapture: captureWindow returned nil for \(item.logString)")
                nilImageCount += 1
                recordCaptureFailure(for: item)
                result.excluded.append(item)
                continue
            }

            guard !image.isTransparent() else {
                MenuBarItemImageCache.diagLog.debug("individualCapture: captured image is transparent for \(item.logString) (\(image.width)x\(image.height))")
                transparentCount += 1
                recordCaptureFailure(for: item)
                result.excluded.append(item)
                continue
            }

            // Record success and cache
            capturedCount += 1
            recordCaptureSuccess(for: item)
            result.images[item.tag] = CapturedImage(
                cgImage: image,
                scale: scale
            )
        }

        MenuBarItemImageCache.diagLog.debug("individualCapture: \(items.count) items -> \(capturedCount) captured, \(nilImageCount) nil, \(transparentCount) transparent, \(skippedCount) skipped (blacklisted)")
        return result
    }

    /// Captures the images of the given menu bar items and returns the result.
    private nonisolated func captureImages(
        of items: [MenuBarItem],
        scale: CGFloat,
        appState: AppState
    ) async -> CaptureResult {
        // Thaw's own control items always capture as transparent via
        // CGWindowListCreateImage, so skip them to avoid the perpetual
        // fail -> blacklist -> cooldown -> retry cycle.
        let capturable = items.filter { !$0.isControlItem }

        // Use individual capture after a move operation, since composite capture
        // doesn't account for overlapping items.
        if await appState.itemManager.lastMoveOperationOccurred(
            within: .seconds(2)
        ) {
            MenuBarItemImageCache.diagLog.debug("Capturing individually due to recent item movement")
            return individualCapture(capturable, scale: scale)
        }

        // Pre-filter off-screen items: hidden section items are positioned past
        // the right edge of the screen. Including them in compositeCapture
        // inflates boundsUnion → CGWindowListCreateImageFromArray returns an
        // image narrower than expected → width mismatch → the whole composite
        // fails for ALL items. Off-screen items are captured by the live refresh
        // loop (refreshImages) instead, so we can safely skip them here.
        //
        // Note: isWindowOnScreen() cannot be used for this — macOS incorrectly
        // reports hidden menu bar items as on-screen (known macOS behaviour).
        let displayID = Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
        let screenFrame = await MainActor.run {
            NSScreen.screens.first { $0.displayID == displayID }?.frame
        }

        // Fetch window bounds once for all items. This single pass is reused for
        // both the off-screen filter and the subsequent compositeCapture, avoiding
        // a redundant system call and eliminating the TOCTOU race where a window
        // could move between the two lookups.
        var onScreenItemsWithBounds: [(item: MenuBarItem, bounds: CGRect)] = []
        var offScreenCount = 0
        var nilBoundsCount = 0

        for item in capturable {
            guard let bounds = Bridging.getWindowBounds(for: item.windowID) else {
                // Window bounds unavailable — skip; neither composite nor
                // individual capture can succeed without position info.
                nilBoundsCount += 1
                continue
            }
            if let screenFrame, !screenFrame.intersects(bounds) {
                offScreenCount += 1
            } else {
                onScreenItemsWithBounds.append((item: item, bounds: bounds))
            }
        }

        if nilBoundsCount > 0 {
            MenuBarItemImageCache.diagLog.debug(
                "captureImages: \(nilBoundsCount)/\(capturable.count) items had no bounds, skipped"
            )
        }
        if offScreenCount > 0 {
            MenuBarItemImageCache.diagLog.debug(
                "captureImages: \(offScreenCount)/\(capturable.count) off-screen items skipped (live refresh handles them)"
            )
        }

        guard !onScreenItemsWithBounds.isEmpty else {
            MenuBarItemImageCache.diagLog.debug(
                "captureImages: no on-screen items to capture for this section"
            )
            return CaptureResult()
        }

        let compositeResult = compositeCapture(onScreenItemsWithBounds, scale: scale)

        if compositeResult.excluded.isEmpty {
            return compositeResult // All items captured successfully.
        }

        MenuBarItemImageCache.diagLog.debug(
            "\(compositeResult.excluded.count)/\(onScreenItemsWithBounds.count) items excluded from composite, retrying individually"
        )

        var individualResult = individualCapture(
            compositeResult.excluded,
            scale: scale
        )

        // Merge the successfully captured images from each result. Keep excluded
        // items as part of the result, so they can be logged elsewhere.
        individualResult.images.merge(compositeResult.images) { _, new in new }

        return individualResult
    }

    /// Lightweight image refresh for the IceBar.
    ///
    /// Performs a single composite capture and crops individual items.
    /// Updates LRU access timestamps for refreshed images to keep them
    /// consistent with the `images` dict (preventing LRU inconsistencies),
    /// but skips full cache management (LRU eviction, failure tracking,
    /// size enforcement, cleanup).
    /// Skips `@Published` updates when images haven't changed visually.
    nonisolated func refreshImages(
        of items: [MenuBarItem],
        scale: CGFloat
    ) async {
        var windowIDs = [CGWindowID]()
        var storage = [CGWindowID: (MenuBarItem, CGRect)]()
        var boundsUnion = CGRect.null

        for item in items {
            guard let bounds = Bridging.getWindowBounds(for: item.windowID) else {
                continue
            }
            windowIDs.append(item.windowID)
            storage[item.windowID] = (item, bounds)
            boundsUnion = boundsUnion.union(bounds)
        }

        guard !windowIDs.isEmpty else {
            MenuBarItemImageCache.diagLog.debug("refreshImages: no items with bounds, skipping")
            return
        }

        guard let compositeImage = ScreenCapture.captureWindows(
            with: windowIDs,
            option: captureOption
        ) else {
            MenuBarItemImageCache.diagLog.debug("refreshImages: capture failed, skipping")
            return
        }

        let expectedWidth = boundsUnion.width * scale
        guard CGFloat(compositeImage.width) == expectedWidth else {
            MenuBarItemImageCache.diagLog.debug("refreshImages: width mismatch (expected \(expectedWidth), got \(compositeImage.width)), skipping")
            return
        }

        guard !compositeImage.isTransparent() else {
            MenuBarItemImageCache.diagLog.debug("refreshImages: composite is transparent, skipping")
            return
        }

        var newImages = [MenuBarItemTag: CapturedImage]()
        for windowID in windowIDs {
            guard let (item, bounds) = storage[windowID] else { continue }
            let cropRect = CGRect(
                x: (bounds.origin.x - boundsUnion.origin.x) * scale,
                y: (bounds.origin.y - boundsUnion.origin.y) * scale,
                width: bounds.width * scale,
                height: bounds.height * scale
            )
            // No per-item isTransparent() here: the composite-level check
            // above already rejects fully-transparent captures. Individual
            // transparent crops are intentional spacers. Failure tracking
            // lives in compositeCapture/individualCapture only.
            guard let image = compositeImage.cropping(to: cropRect) else {
                continue
            }
            newImages[item.tag] = CapturedImage(cgImage: image, scale: scale)
        }

        guard !newImages.isEmpty, !Task.isCancelled else { return }

        await MainActor.run { [newImages] in
            var updatedCount = 0
            for (tag, newImage) in newImages where !CapturedImage.isVisuallyEqual(self.images[tag], newImage) {
                self.images[tag] = newImage
                accessCounter += 1
                accessTimestamps[tag] = accessCounter
                updatedCount += 1
            }
            if updatedCount > 0 {
                MenuBarItemImageCache.diagLog.debug("refreshImages: ✓ updated \(updatedCount)/\(newImages.count) items (visually changed)")
            }
        }
    }

    /// Captures the images of the menu bar items in the given section and returns
    /// a dictionary containing the images, keyed by their menu bar item tags.
    private func captureImages(
        for section: MenuBarSection.Name,
        scale: CGFloat,
        appState: AppState
    ) async -> [MenuBarItemTag: CapturedImage] {
        let items = await appState.itemManager.itemCache.managedItems(
            for: section
        )
        let captureResult = await captureImages(
            of: items,
            scale: scale,
            appState: appState
        )
        if !captureResult.excluded.isEmpty {
            MenuBarItemImageCache.diagLog.debug(
                "captureImages: \(captureResult.excluded.count) items failed capture"
            )
        }
        return captureResult.images
    }

    // MARK: Failed Capture Management

    /// Checks if an item should be skipped due to repeated capture failures.
    private func shouldSkipCapture(for item: MenuBarItem) -> Bool {
        guard let failed = failedCaptures[item.tag] else {
            return false
        }

        // If failed too many times and within cooldown period, skip
        if failed.failureCount >= Self.maxFailuresBeforeBlacklist {
            let timeSinceFailure = Date().timeIntervalSince(
                failed.lastFailureTime
            )
            if timeSinceFailure < Self.blacklistCooldownSeconds {
                return true
            } else {
                // Cooldown expired, reset failure count
                failedCaptures.removeValue(forKey: item.tag)
                return false
            }
        }

        return false
    }

    /// Records a capture failure for an item.
    private func recordCaptureFailure(for item: MenuBarItem) {
        let now = Date()
        let existing = failedCaptures[item.tag]

        if let existing = existing {
            let newCount = existing.failureCount + 1
            failedCaptures[item.tag] = FailedCapture(
                tag: item.tag,
                failureCount: newCount,
                lastFailureTime: now
            )

            // Log when an item reaches blacklist threshold
            if newCount == Self.maxFailuresBeforeBlacklist {
                MenuBarItemImageCache.diagLog.info(
                    "Item blacklisted after \(newCount) failures: \(item.logString) (will retry after \(Self.blacklistCooldownSeconds)s cooldown)"
                )
            }
        } else {
            failedCaptures[item.tag] = FailedCapture(
                tag: item.tag,
                failureCount: 1,
                lastFailureTime: now
            )
        }

        // Clean up old failed entries
        cleanupOldFailedEntries()
    }

    /// Records a successful capture for an item (resets failure count).
    private func recordCaptureSuccess(for item: MenuBarItem) {
        if let existing = failedCaptures.removeValue(forKey: item.tag), existing.failureCount >= 2 {
            MenuBarItemImageCache.diagLog.info(
                "Item recovered after \(existing.failureCount) previous failures: \(item.logString)"
            )
        }
    }

    /// Cleans up old failed capture entries that have expired.
    private func cleanupOldFailedEntries() {
        let cutoff = Date().addingTimeInterval(-Self.blacklistCooldownSeconds)
        failedCaptures = failedCaptures.filter { _, failed in
            failed.lastFailureTime > cutoff
        }
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
        let failedCleared = failedCaptures.count
        failedCaptures.removeAll()
        MenuBarItemImageCache.diagLog.info(
            "Manual cache cleanup completed: removed \(removedCount) invalid entries, cleared \(failedCleared) failed captures"
        )
    }

    /// Logs detailed cache information for debugging memory issues.
    /// This method is NOT called automatically - you must call it explicitly.
    func logCacheStatus(_ context: String = "Manual check") {
        let imageSize = images.count
        let lruSize = accessTimestamps.count
        let maxSize = Self.maxCacheSize
        let usagePercent = (imageSize * 100) / maxSize
        let failedCount = failedCaptures.count
        let blacklistedCount = failedCaptures.values.filter {
            $0.failureCount >= Self.maxFailuresBeforeBlacklist
        }.count

        let lruSorted = accessTimestamps.sorted { $0.value < $1.value }
        let lruDescription = lruSorted.map { "\($0.key)" }.joined(separator: ", ")

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

    // MARK: Update Cache

    /// Updates the cache for the given sections, without checking whether
    /// caching is necessary.
    func updateCacheWithoutChecks(sections: [MenuBarSection.Name]) async {
        guard let appState else {
            MenuBarItemImageCache.diagLog.warning("updateCacheWithoutChecks: appState is nil, aborting")
            return
        }

        let hasScreenRecording = await appState.hasPermission(.screenRecording)
        guard hasScreenRecording else {
            MenuBarItemImageCache.diagLog.debug("updateCacheWithoutChecks: no screen recording permission, aborting")
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

            let sectionImages = await captureImages(
                for: section,
                scale: scale,
                appState: appState
            )

            guard !sectionImages.isEmpty else {
                // Expected for off-screen sections (e.g. hidden): live refresh
                // (refreshImages) handles those items. Only a real concern for
                // the visible section — check compositeCapture logs for details.
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

        // Get the set of valid item tags from all sections to clean up stale entries
        let allValidTags = await Set(
            appState.itemManager.itemCache.managedItems.map(\.tag)
        )

        await MainActor.run { [newImages, allValidTags] in
            let beforeCount = images.count

            // Tags with recent capture failures should keep their cached images
            // even if the item temporarily left the item cache (e.g. a transient
            // menu bar item whose window briefly disappeared). This prevents
            // the IceBar and search from showing empty icons while the item's
            // app is still running.
            let recentlyFailedTags = Set(failedCaptures.keys)

            // Remove images for items that no longer exist in the item cache,
            // but preserve images for items that have recent capture failures
            // (they may reappear shortly with a new window ID).
            // Use matchesIgnoringWindowID for non-system items so disk-loaded
            // entries are not incorrectly evicted when their windowID is nil.
            images = images.filter { key, _ in
                if key.isSystemItem {
                    return allValidTags.contains(key) || recentlyFailedTags.contains(key)
                }
                return containsTagMatchingIgnoringWindowID(allValidTags, target: key) ||
                    containsTagMatchingIgnoringWindowID(recentlyFailedTags, target: key)
            }

            // Additional cleanup: Remove entries with invalid window information,
            // but again preserve recently-failed items.
            _ = validateAndCleanupInvalidEntries(preserving: recentlyFailedTags)

            // Mark all newly captured images as most recently used
            for tag in newImages.keys {
                accessCounter += 1
                accessTimestamps[tag] = accessCounter
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

    private func containsTagMatchingIgnoringWindowID(
        _ tags: Set<MenuBarItemTag>,
        target: MenuBarItemTag
    ) -> Bool {
        for tag in tags where tag.matchesIgnoringWindowID(target) {
            return true
        }
        return false
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

    /// Clears all cached images and failure tracking.
    @MainActor
    func clearAll() {
        images.removeAll()
        accessTimestamps.removeAll()
        accessCounter = 0
        failedCaptures.removeAll()
    }

    // MARK: Cache Failed

    /// Returns a Boolean value that indicates whether caching menu bar items
    /// failed for the given section.
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
