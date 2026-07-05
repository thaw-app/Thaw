//
//  MenuBarItemImageCache.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import os.lock

/// Cache for menu bar item images.
final class MenuBarItemImageCache: ObservableObject, @unchecked Sendable {
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

        /// Whether the capture is effectively blank for UI thumbnail purposes.
        var isEffectivelyBlank: Bool {
            cgImage.isTransparent(alphaThreshold: 0.05)
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

    private let failedCapturesLock = OSAllocatedUnfairLock<[MenuBarItemTag: FailedCapture]>(initialState: [:])

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

    /// Tracks whether the MenuBarLayoutSettingsPane has been opened at least once.
    /// Used to gate background cache prewarming so captures only occur after the user
    /// has accessed the layout settings.
    @Published private(set) var settingsPaneHasBeenOpened = false

    /// Whether the per-item hotkey list in the Hotkeys settings pane is expanded.
    /// While collapsed, the pane has no visible item-icon consumer, so the live
    /// capture loop stays off rather than paying the off-screen SkyLight capture
    /// cost for items the user cannot see.
    @Published private(set) var isItemHotkeyListExpanded = false

    /// Updates isItemHotkeyListExpanded from the Hotkeys settings UI.
    func setItemHotkeyListExpanded(_ expanded: Bool) {
        guard isItemHotkeyListExpanded != expanded else {
            return
        }
        isItemHotkeyListExpanded = expanded
    }

    deinit {
        memoryPressureSource?.cancel()
        currentUpdateTask?.cancel()
        liveRefreshTask?.cancel()
    }

    // MARK: Setup

    /// Sets up the cache.
    static nonisolated func captureDisplayID(
        itemCacheDisplayID: CGDirectDisplayID?,
        activeMenuBarDisplayID: CGDirectDisplayID?,
        mainDisplayID: CGDirectDisplayID
    ) -> CGDirectDisplayID {
        itemCacheDisplayID ?? activeMenuBarDisplayID ?? mainDisplayID
    }

    @MainActor
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()

        // Try to load cached images from disk
        loadFromDisk()

        // Only prewarm if a visible consumer exists at setup time.
        // Background prewarming is gated by settingsPaneHasBeenOpened.
        let hasVisible = hasVisibleCaptureConsumer()
        guard hasVisible else {
            return
        }

        // Keep a fresh layout snapshot ready so opening the layout settings
        // pane does not need to capture every item from scratch.
        currentUpdateTask?.cancel()
        currentUpdateTask = Task { [weak self] in
            await self?.refreshVisibleConsumersOrPrewarmLayoutCache()
        }
    }

    /// Marks that the MenuBarLayoutSettingsPane has been opened.
    /// Call this from the pane's onAppear or task modifier to enable background cache prewarming.
    @MainActor
    func markSettingsPaneOpened() {
        settingsPaneHasBeenOpened = true
    }

    // MARK: Disk Persistence

    /// Path to the cache file in Caches directory.
    private static var cacheFileURL: URL? {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return cacheDir?.appendingPathComponent("com.stonerl.thaw/imageCache.json")
    }

    /// Maximum age of disk cache before it's considered stale (30 seconds).
    private static let maxCacheAgeSeconds: TimeInterval = 30

    /// Bump when the capture/display semantics change enough that old images
    /// can be misleading.
    private static let cacheVersion = 2

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

                let tagString = tag.tagIdentifier
                return (tagString, pngData)
            }.compactMap(\.self)

            guard cacheData.count == snapshot.count else { return }

            do {
                let directoryURL = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

                let json: [String: Any] = [
                    "version": Self.cacheVersion,
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

                let version = json["version"] as? Int
                if version != Self.cacheVersion {
                    MenuBarItemImageCache.diagLog.debug("Disk cache version \(version ?? -1) is stale, deleting cache")
                    try? FileManager.default.removeItem(at: url)
                    return
                }

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

            let itemCacheChangePublisher: AnyPublisher<Void, Never> = appState.itemManager.$itemCache
                .map(Self.captureInvalidationKey)
                .removeDuplicates()
                .dropFirst()
                .map { _ in () }
                .eraseToAnyPublisher()

            Publishers.MergeMany([
                spaceChangePublisher,
                screenChangePublisher,
                itemCacheChangePublisher,
            ])
            .debounce(
                for: .milliseconds(Constants.MenuBarTuning.imageCaptureObserverDebounceMilliseconds),
                scheduler: DispatchQueue.main
            )
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                // Only trigger capture if a visible consumer exists or the settings pane
                // has been opened at least once (itemCacheChangePublisher may indicate
                // new items that the layout pane will need).
                let nav = self.makeNavigationStateSnapshot()
                let hasVisible = self.hasVisibleCaptureConsumer(nav: nav)
                let settingsOpened = self.settingsPaneHasBeenOpened
                guard hasVisible || settingsOpened else {
                    return
                }
                self.currentUpdateTask?.cancel()
                self.currentUpdateTask = Task { [weak self, settingsOpened] in
                    await self?.refreshVisibleConsumersOrPrewarmLayoutCache(
                        allowBackgroundCapture: settingsOpened
                    )
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

            // Start/stop the live refresh when the Hotkeys pane's per-item list
            // is expanded or collapsed, since that gates its capture consumer.
            $isItemHotkeyListExpanded
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
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

    /// Semantic cache state that requires a new item-image capture. Position is
    /// deliberately absent: routine AX geometry jitter changes `ItemCache`
    /// equality but not the icon pixels or crop dimensions, and was the source
    /// of the observer-driven capture feedback loop.
    struct CaptureInvalidationKey: Equatable {
        struct Entry: Equatable, Comparable {
            let section: String
            let identifier: String
            let windowID: CGWindowID
            let width: CGFloat
            let height: CGFloat
            let isOnScreen: Bool

            static func < (lhs: Entry, rhs: Entry) -> Bool {
                if lhs.section != rhs.section { return lhs.section < rhs.section }
                if lhs.identifier != rhs.identifier { return lhs.identifier < rhs.identifier }
                return lhs.windowID < rhs.windowID
            }
        }

        let displayID: CGDirectDisplayID?
        let entries: [Entry]
    }

    static nonisolated func captureInvalidationKey(
        _ cache: MenuBarItemManager.ItemCache
    ) -> CaptureInvalidationKey {
        let entries = MenuBarSection.Name.allCases.flatMap { section in
            cache[section].map { item in
                CaptureInvalidationKey.Entry(
                    section: section.rawValue,
                    identifier: item.uniqueIdentifier,
                    windowID: item.windowID,
                    width: item.bounds.width,
                    height: item.bounds.height,
                    isOnScreen: item.isOnScreen
                )
            }
        }.sorted()
        return CaptureInvalidationKey(displayID: cache.displayID, entries: entries)
    }

    /// Snapshot of navigation state read in a single MainActor hop.
    struct NavigationStateSnapshot {
        let isIceBarPresented: Bool
        let isSearchPresented: Bool
        let isAppFrontmost: Bool
        let isSettingsPresented: Bool
        let settingsNavigationIdentifier: SettingsNavigationIdentifier?
        let isItemHotkeyListExpanded: Bool
    }

    /// Constructs a NavigationStateSnapshot from the current appState in a single MainActor hop.
    /// Centralizes snapshot construction to avoid duplication across multiple call sites.
    @MainActor
    private func makeNavigationStateSnapshot() -> NavigationStateSnapshot {
        guard let appState else {
            return NavigationStateSnapshot(
                isIceBarPresented: false,
                isSearchPresented: false,
                isAppFrontmost: false,
                isSettingsPresented: false,
                settingsNavigationIdentifier: nil,
                isItemHotkeyListExpanded: false
            )
        }
        return NavigationStateSnapshot(
            isIceBarPresented: appState.navigationState.isIceBarPresented,
            isSearchPresented: appState.navigationState.isSearchPresented,
            isAppFrontmost: appState.navigationState.isAppFrontmost,
            isSettingsPresented: appState.navigationState.isSettingsPresented,
            settingsNavigationIdentifier: appState.navigationState.settingsNavigationIdentifier,
            isItemHotkeyListExpanded: isItemHotkeyListExpanded
        )
    }

    /// Refreshes the cache for currently visible consumers, or keeps a warm
    /// background snapshot ready for the layout settings pane when no consumer
    /// is visible.
    private func refreshVisibleConsumersOrPrewarmLayoutCache(allowBackgroundCapture: Bool = false) async {
        guard appState != nil else {
            return
        }

        let nav = await MainActor.run { makeNavigationStateSnapshot() }

        let hasVisibleConsumer = hasVisibleCaptureConsumer(nav: nav)

        // Early-return unless a visible consumer exists or background capture is explicitly allowed.
        // Background capture is gated by settingsPaneHasBeenOpened to avoid unnecessary full-screen
        // captures when the user has never opened the layout settings pane.
        guard hasVisibleConsumer || (allowBackgroundCapture && settingsPaneHasBeenOpened) else {
            return
        }

        if hasVisibleConsumer {
            await updateCache(nav: nav)
        } else {
            await updateCache(
                sections: MenuBarSection.Name.allCases,
                allowBackgroundCapture: true,
                nav: nav
            )
        }
    }

    /// Returns whether any visible surface currently needs live item captures.
    private func hasVisibleCaptureConsumer(nav: NavigationStateSnapshot) -> Bool {
        if nav.isIceBarPresented || nav.isSearchPresented {
            return true
        }

        guard nav.isAppFrontmost, nav.isSettingsPresented else {
            return false
        }
        switch nav.settingsNavigationIdentifier {
        case .menuBarLayout:
            return true
        case .hotkeys:
            // Only the expanded per-item hotkey list consumes item icons. Read
            // from the snapshot so this stays race-free when called off the main
            // actor (e.g. from refreshVisibleConsumersOrPrewarmLayoutCache).
            return nav.isItemHotkeyListExpanded
        default:
            return false
        }
    }

    /// Convenience overload that reads current state on MainActor when no snapshot is provided.
    @MainActor
    private func hasVisibleCaptureConsumer() -> Bool {
        guard let appState else {
            return false
        }
        let nav = NavigationStateSnapshot(
            isIceBarPresented: appState.navigationState.isIceBarPresented,
            isSearchPresented: appState.navigationState.isSearchPresented,
            isAppFrontmost: appState.navigationState.isAppFrontmost,
            isSettingsPresented: appState.navigationState.isSettingsPresented,
            settingsNavigationIdentifier: appState.navigationState.settingsNavigationIdentifier,
            isItemHotkeyListExpanded: isItemHotkeyListExpanded
        )
        return hasVisibleCaptureConsumer(nav: nav)
    }

    /// Starts or stops the live image refresh loop based on navigation state.
    @MainActor
    private func startLiveRefreshIfNeeded() {
        guard appState != nil else {
            liveRefreshTask?.cancel()
            liveRefreshTask = nil
            return
        }

        // Compute visibility using centralized snapshot and helper to avoid duplication.
        // Wrapping in Task since this is called from synchronous sink closures on main thread.
        Task { [weak self] in
            guard let self else { return }
            let nav = await MainActor.run {
                self.makeNavigationStateSnapshot()
            }
            let needsRefresh = self.hasVisibleCaptureConsumer(nav: nav)

            if needsRefresh {
                // Already running — don't restart
                guard self.liveRefreshTask == nil else { return }
                MenuBarItemImageCache.diagLog.debug(
                    "Starting live refresh (iceBar=\(nav.isIceBarPresented), search=\(nav.isSearchPresented), settings=\(nav.isSettingsPresented))"
                )
                self.liveRefreshTask = Task { [weak self] in
                    guard let self else { return }
                    await self.runLiveRefreshLoop()
                }
            } else {
                if self.liveRefreshTask != nil {
                    MenuBarItemImageCache.diagLog.debug("Stopping live refresh")
                }
                self.liveRefreshTask?.cancel()
                self.liveRefreshTask = nil
            }
        }
    }

    /// The centralized live refresh loop for image updates.
    ///
    /// Runs a single capture loop that serves all consumer views (IceBar,
    /// Search, Layout Settings) instead of each view running its own loop.
    /// Heavy work (`refreshImages`) is `nonisolated` and runs off the main
    /// actor — only navigation state reads happen on `@MainActor`.
    /// Uses `self.appState` (weak property) to avoid retain cycle via
    /// the task's async stack frame.
    @MainActor
    private func runLiveRefreshLoop() async {
        MenuBarItemImageCache.diagLog.debug("Live refresh loop started")

        while !Task.isCancelled {
            guard let appState = self.appState else { break }
            var interval = appState.settings.advanced.iconRefreshInterval
            guard interval > 0 else {
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            if #available(macOS 27, *) {
                // Each macOS 27 refresh is a full MenuBarAgent hosting-window
                // screenshot (plus an AX walk for concealed sections) — far
                // heavier than the legacy per-window capture. A sub-second cadence
                // storms the CPU (~7 captures/s observed) and makes captures lag or
                // fail, which is what leaves Hidden icons blank and interferes with
                // moves. Layout-UI icons are near-static, so clamp to a calmer floor.
                interval = max(interval, Constants.MenuBarTuning.minimumLiveImageRefreshInterval)
            }
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
            let isLayoutPane = nav.isSettingsPresented
                && nav.settingsNavigationIdentifier == .menuBarLayout
            // The Hotkeys pane only needs item icons while its per-item list
            // disclosure is expanded.
            let isHotkeyListVisible = nav.isSettingsPresented
                && nav.settingsNavigationIdentifier == .hotkeys
                && isItemHotkeyListExpanded
            if nav.isSearchPresented {
                sections = [.visible]
            } else if isLayoutPane || isHotkeyListVisible {
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

            // Hoisted: these are tick-global, not per-section.
            if appState.itemManager.lastMoveOperationOccurred(within: .seconds(2)) {
                continue
            }
            if appState.itemManager.isResettingLayout {
                continue
            }

            let scale = screen.backingScaleFactor

            // macOS 27: items are composited inside MenuBarAgent and have
            // synthetic windowIDs with no CGS window, so the CGS/SkyLight
            // refreshImages path (Bridging.getWindowBounds → cgsGetScreenRectForWindow)
            // fails for every item — pure spam, never updating anything. The only
            // capture that works is the AX-bounds hosting-window screenshot, which
            // updateCacheWithoutChecks already routes to (axBoundsCapture). Use it
            // here so the periodic refresh actually refreshes on 27.
            if #available(macOS 27, *) {
                await updateCacheWithoutChecks(sections: sections)
                continue
            }

            // Partition by capture path: visible items refresh via SCK
            // (leak-free); hidden + always-hidden items refresh via SkyLight,
            // batched into a single call per tick to amortize the irreducible
            // per-call dictionary leak.
            var offscreenBatch = [MenuBarItem]()
            var offscreenSectionLabels = [String]()

            for section in sections {
                let items = appState.itemManager.itemCache.managedItems(for: section)
                guard !items.isEmpty else { continue }

                if section == .visible {
                    MenuBarItemImageCache.diagLog.debug("liveRefresh (SCK): section=\(section.logString) displayID=\(screen.displayID) backingScaleFactor=\(Double(scale)) hasNotch=\(screen.hasNotch) items=\(items.count) menuBarHeight=\(Double(screen.getMenuBarHeightEstimate()))")
                    await refreshImages(of: items, scale: scale, viaSCK: true)
                } else {
                    offscreenBatch.append(contentsOf: items)
                    offscreenSectionLabels.append("\(section.logString)=\(items.count)")
                }
            }

            if !offscreenBatch.isEmpty {
                MenuBarItemImageCache.diagLog.debug("liveRefresh (SkyLight): batched \(offscreenBatch.count) offscreen items [\(offscreenSectionLabels.joined(separator: ", "))]")
                await refreshImages(of: offscreenBatch, scale: scale)
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
    ) async -> CaptureResult {
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

        let compositeImage = await ScreenCapture.captureWindowsAsync(
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
    ) async -> CaptureResult {
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

            let image = await ScreenCapture.captureWindowAsync(
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
    /// Captures item thumbnails on macOS 27 where status items are no longer
    /// independent CGS windows.
    ///
    /// On macOS 27, `Bridging.getWindowBounds` returns nil for every item
    /// (their `windowID`s are synthetic FNV-1a hashes, not real CGS IDs), and
    /// `SLWindowListCreateImageFromArray` cannot capture MenuBarAgent's content.
    /// Instead this captures `MenuBarAgent`'s menu bar hosting window — which
    /// renders every status item on a transparent background — and crops each
    /// item out of it using the AX-provided bounds in `item.bounds`. Capturing
    /// the hosting window (rather than a display region) keeps the menu bar fill
    /// and the wallpaper out of the thumbnails.
    /// Checks which of the given items currently render as blank pixels in the
    /// real menu bar, independent of this cache's own stored images.
    ///
    /// A restriction-reflow re-composite can leave an allowed item as an
    /// on-band "AX ghost": hit-testing and tooltips still resolve it at the
    /// right coordinates, but nothing is drawn there. Whether the assertion
    /// pulse fixed that isn't knowable from cache state alone (this cache
    /// often holds no entry for a `.visible`-section item at all, since
    /// `runLiveRefreshLoop` only captures while a Thaw UI surface — Settings,
    /// Search, IceBar — is open). A fresh hosting-window screenshot is the
    /// only ground truth for whether the OS actually redrew the glyph.
    @available(macOS 27, *)
    nonisolated func itemsRenderingBlank(
        among items: [MenuBarItem],
        displayID: CGDirectDisplayID
    ) async -> Set<MenuBarItemTag> {
        guard !items.isEmpty,
              let capture = await ScreenCapture.captureMenuBarHostingWindowAsync(displayID: displayID)
        else {
            return []
        }

        let composite = capture.image
        let windowFrame = capture.windowFrame
        let scale = capture.scale
        let imageBounds = CGRect(x: 0, y: 0, width: composite.width, height: composite.height)

        var blankTags = Set<MenuBarItemTag>()
        for item in items {
            guard windowFrame.intersects(item.bounds) else { continue }
            let rawCropRect = CGRect(
                x: (item.bounds.minX - windowFrame.minX) * scale,
                y: (item.bounds.minY - windowFrame.minY) * scale,
                width: item.bounds.width * scale,
                height: item.bounds.height * scale
            )
            let cropRect = rawCropRect.integral.intersection(imageBounds)
            guard !cropRect.isNull, !cropRect.isEmpty,
                  let croppedImage = composite.cropping(to: cropRect)
            else {
                continue
            }
            if croppedImage.isTransparent() {
                blankTags.insert(item.tag)
            }
        }
        return blankTags
    }

    @available(macOS 27, *)
    private nonisolated func axBoundsCapture(
        _ itemsWithBounds: [(item: MenuBarItem, bounds: CGRect)],
        scale _: CGFloat,
        displayID: CGDirectDisplayID
    ) async -> CaptureResult {
        guard !itemsWithBounds.isEmpty else { return CaptureResult() }

        guard let capture = await ScreenCapture.captureMenuBarHostingWindowAsync(displayID: displayID) else {
            MenuBarItemImageCache.diagLog.warning(
                "axBoundsCapture: captureMenuBarHostingWindowAsync failed for \(itemsWithBounds.count) items"
            )
            var fail = CaptureResult()
            fail.excluded = itemsWithBounds.map(\.item)
            return fail
        }

        let composite = capture.image
        let windowFrame = capture.windowFrame
        let scale = capture.scale
        let imageBounds = CGRect(x: 0, y: 0, width: composite.width, height: composite.height)

        MenuBarItemImageCache.diagLog.debug(
            "axBoundsCapture: hosting window \(composite.width)×\(composite.height)px, " +
                "cropping \(itemsWithBounds.count) items"
        )

        var result = CaptureResult()

        for (item, bounds) in itemsWithBounds {
            if shouldSkipCapture(for: item) {
                result.excluded.append(item)
                continue
            }

            // A concealed / off-screen item reports phantom bounds far below
            // the bar (macOS 27 parks them at y≈1428, well outside the ~30pt
            // hosting window even though they're still within the screen). Such
            // bounds would crop to an empty rect; exclude them WITHOUT recording
            // a capture failure so they aren't blacklisted and keep their last
            // good image. `windowFrame` shares the item's coordinate space (see
            // the crop math below), so a plain intersection check suffices.
            if !windowFrame.intersects(bounds) {
                MenuBarItemImageCache.diagLog.debug(
                    "axBoundsCapture: \(item.logString) bounds \(bounds) outside hosting " +
                        "window \(windowFrame); keeping prior image"
                )
                result.excluded.append(item)
                continue
            }

            // Map the item's global (Y-down) frame into the hosting window's
            // image: subtract the window origin, then scale to pixels. CGImage
            // rows run top-down, matching the Y-down screen convention.
            //
            // `.integral` rounds the rect outward to whole pixels so a sub-pixel
            // origin/size never shaves the glyph's edge (the intermittent "cut
            // icon"), and the intersection clamps it inside the composite so an
            // edge item's slightly-oversized rect can't spill past the image and
            // either fail or capture a shifted, wrong-looking region.
            let rawCropRect = CGRect(
                x: (bounds.minX - windowFrame.minX) * scale,
                y: (bounds.minY - windowFrame.minY) * scale,
                width: bounds.width * scale,
                height: bounds.height * scale
            )
            let cropRect = rawCropRect.integral.intersection(imageBounds)

            guard !cropRect.isNull, !cropRect.isEmpty, let croppedImage = composite.cropping(to: cropRect) else {
                MenuBarItemImageCache.diagLog.debug(
                    "axBoundsCapture: cropping failed for \(item.logString) " +
                        "rawCropRect=\(rawCropRect) clamped=\(cropRect)"
                )
                recordCaptureFailure(for: item)
                result.excluded.append(item)
                continue
            }

            guard !croppedImage.isTransparent(alphaThreshold: 0.05) else {
                // Denylisted hiding-unsupported apps transiently render blank during
                // Assessment Mode reflows — the assertion recomposites the whole
                // bar, temporarily clearing their glyph until their own update
                // cycle re-renders it. Counting those transient blanks as failures
                // blacklists the item for 30 s, causing the layout bar to show grey
                // boxes long after the bar has settled. Skip without recording a
                // failure so the item retains its last good image and recovers on
                // the next refresh cycle.
                if item.tag.isHidingUnsupported {
                    MenuBarItemImageCache.diagLog.debug(
                        "axBoundsCapture: blank image for denylisted hiding-unsupported \(item.logString); " +
                            "skipping without failure (will recover on next refresh)"
                    )
                    result.excluded.append(item)
                    continue
                }
                MenuBarItemImageCache.diagLog.debug(
                    "axBoundsCapture: blank image for \(item.logString)"
                )
                recordCaptureFailure(for: item)
                result.excluded.append(item)
                continue
            }

            recordCaptureSuccess(for: item)
            result.images[item.tag] = CapturedImage(cgImage: croppedImage, scale: scale)
        }

        return result
    }

    private nonisolated func captureImages(
        of items: [MenuBarItem],
        scale: CGFloat,
        appState: AppState,
        freshBounds: Bool = false
    ) async -> CaptureResult {
        // Thaw's section-divider control items capture as transparent via
        // CGWindowListCreateImage on macOS <=26, so skip them there. On macOS
        // 27 the visible Thaw icon is composited inside MenuBarAgent and crops
        // correctly from the hosting-window screenshot (axBoundsCapture).
        let capturable: [MenuBarItem] = if #available(macOS 27, *) {
            items.filter { !$0.isControlItem || $0.tag == .visibleControlItem }
        } else {
            items.filter { !$0.isControlItem }
        }

        // macOS 27: status items live inside MenuBarAgent — no real CGWindowIDs.
        // Skip the CGS/SkyLight path entirely and use AX-provided bounds with a
        // display-region SCK screenshot instead.
        if #available(macOS 27, *) {
            let displayID = await MainActor.run {
                Self.captureDisplayID(
                    itemCacheDisplayID: appState.itemManager.itemCache.displayID,
                    activeMenuBarDisplayID: Bridging.getActiveMenuBarDisplayID(),
                    mainDisplayID: CGMainDisplayID()
                )
            }
            let screenFrame = await MainActor.run {
                NSScreen.screens.first { $0.displayID == displayID }?.frame
            }

            // Crop against FRESH live AX bounds, not the cached `item.bounds`.
            // A just-revealed Hidden item still carries its stale snapshot
            // position in the cache, so cropping with it grabs a neighbor's
            // pixels from the live screenshot (e.g. BetterDisplay shows the Sound
            // icon). Only the Hidden/Always-Hidden sections need this; the Visible
            // section's cache bounds are already fresh and it is captured far too
            // often to pay for an extra all-apps AX walk each time.
            var liveBoundsByID: [String: CGRect] = [:]
            if freshBounds {
                let liveItems = await MenuBarItem.getMenuBarItems(option: [.onScreen, .activeSpace])
                liveBoundsByID = Dictionary(
                    liveItems.map { ($0.uniqueIdentifier, $0.bounds) },
                    uniquingKeysWith: { first, _ in first }
                )
            }

            var axItems: [(item: MenuBarItem, bounds: CGRect)] = []
            for item in capturable {
                let bounds: CGRect
                if freshBounds {
                    // freshBounds means the cached `item.bounds` are explicitly
                    // distrusted (the item may have shifted in a reflow). If the
                    // live AX walk didn't return THIS item — its identity drifted
                    // (iStat rewrites its title), or it briefly fell out of the
                    // enumeration during a conceal/reflow — we must NOT fall back
                    // to the stale cached bounds: after a leftward reflow those
                    // bounds now overlap a *neighbor*, so cropping there stamps the
                    // neighbor's glyph onto this item's tag (e.g. CodexBar's icon
                    // showing up on an iStat slot). Skip instead, keeping the
                    // item's last-good image until a clean live bound is available.
                    guard let liveBounds = liveBoundsByID[item.uniqueIdentifier] else {
                        MenuBarItemImageCache.diagLog.debug(
                            "captureImages: no live bounds for \(item.logString); " +
                                "keeping prior image (skipping stale-bounds crop)"
                        )
                        continue
                    }
                    bounds = liveBounds
                } else {
                    bounds = item.bounds
                }
                guard !bounds.isEmpty else { continue }
                // items.bounds is in global screen coords (Y-down); NSScreen.frame
                // is in AppKit coords (Y-up) — but both share the same X axis and
                // ranges overlap for on-screen items, so intersects() works as a
                // coarse off-screen filter (negative-X hidden items are excluded).
                if let screenFrame, !screenFrame.intersects(bounds) { continue }
                axItems.append((item: item, bounds: bounds))
            }

            guard !axItems.isEmpty else {
                MenuBarItemImageCache.diagLog.debug(
                    "captureImages: no on-screen items to capture for this section (macOS 27)"
                )
                return CaptureResult()
            }

            return await axBoundsCapture(axItems, scale: scale, displayID: displayID)
        }

        // Use individual capture after a move operation, since composite capture
        // doesn't account for overlapping items.
        if await appState.itemManager.lastMoveOperationOccurred(
            within: .seconds(2)
        ) {
            MenuBarItemImageCache.diagLog.debug("Capturing individually due to recent item movement")
            return await individualCapture(capturable, scale: scale)
        }

        // Pre-filter off-screen items: hidden section items are positioned past
        // the left edge of the screen. Including them in compositeCapture
        // inflates boundsUnion → CGWindowListCreateImageFromArray returns an
        // image narrower than expected → width mismatch → the whole composite
        // fails for ALL items. Off-screen items are captured by the live
        // refresh loop (refreshImages) instead, so we can safely skip them here.
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

        let compositeResult = await compositeCapture(onScreenItemsWithBounds, scale: scale)

        if compositeResult.excluded.isEmpty {
            return compositeResult // All items captured successfully.
        }

        MenuBarItemImageCache.diagLog.debug(
            "\(compositeResult.excluded.count)/\(onScreenItemsWithBounds.count) items excluded from composite, retrying individually"
        )

        var individualResult = await individualCapture(
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
        scale: CGFloat,
        viaSCK: Bool = false
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

        // Capture path: SCK is leak-free but display-bounded, so only use it
        // when the caller knows all items are on-screen (visible section).
        // SkyLight is required for items positioned past the display's left
        // edge (hidden / always-hidden); both SCK filter shapes fail there
        // (display+including → -3812, desktopIndependentWindow → -3811). Each
        // SkyLight call leaks one CFMutableDictionary inside
        // SLSWindowListCreateImageFromArrayProxying; that floor stays until
        // Apple fixes SCK or the framework leak.
        let compositeImage: CGImage? = if viaSCK {
            await ScreenCapture.captureWindowsAsync(
                with: windowIDs,
                option: captureOption
            )
        } else {
            ScreenCapture.captureWindows(
                with: windowIDs,
                option: captureOption
            )
        }
        guard let compositeImage else {
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
        let revealedSection = await MainActor.run {
            appState.menuBarManager.simpleItemHider?.revealedSection
        }
        let shouldUseFreshBounds = section != .visible && revealedSection == section
        let captureResult = await captureImages(
            of: items,
            scale: scale,
            appState: appState,
            // Revealed concealed sections need fresh AX bounds because cached
            // snapshot bounds are stale while MenuBarAgent temporarily publishes
            // their live glyphs. Visible uses its cache-cycle bounds: an extra
            // all-items AX walk can mismatch dynamic items and crop neighbors.
            freshBounds: shouldUseFreshBounds
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
    /// Whether a capture of `item` would currently be attempted, rather than
    /// skipped because it's blacklisted after repeated failures. The Thaw Bar
    /// uses this to avoid revealing (and flashing) the menu bar for an item that
    /// can't be captured anyway.
    nonisolated func wouldAttemptCapture(of item: MenuBarItem) -> Bool {
        !shouldSkipCapture(for: item)
    }

    private func shouldSkipCapture(for item: MenuBarItem) -> Bool {
        failedCapturesLock.withLock { dict in
            guard let failed = dict[item.tag] else {
                return false
            }

            if failed.failureCount >= Self.maxFailuresBeforeBlacklist {
                let timeSinceFailure = Date().timeIntervalSince(
                    failed.lastFailureTime
                )
                if timeSinceFailure < Self.blacklistCooldownSeconds {
                    return true
                } else {
                    dict.removeValue(forKey: item.tag)
                    return false
                }
            }

            return false
        }
    }

    /// Records a capture failure for an item.
    private func recordCaptureFailure(for item: MenuBarItem) {
        let now = Date()
        failedCapturesLock.withLock { dict in
            let existing = dict[item.tag]

            if let existing {
                let newCount = existing.failureCount + 1
                dict[item.tag] = FailedCapture(
                    tag: item.tag,
                    failureCount: newCount,
                    lastFailureTime: now
                )

                if newCount == Self.maxFailuresBeforeBlacklist {
                    MenuBarItemImageCache.diagLog.info(
                        "Item blacklisted after \(newCount) failures: \(item.logString) (will retry after \(Self.blacklistCooldownSeconds)s cooldown)"
                    )
                }
            } else {
                dict[item.tag] = FailedCapture(
                    tag: item.tag,
                    failureCount: 1,
                    lastFailureTime: now
                )
            }

            let cutoff = now.addingTimeInterval(-Self.blacklistCooldownSeconds)
            dict = dict.filter { _, failed in
                failed.lastFailureTime > cutoff
            }
        }
    }

    /// Records a successful capture for an item (resets failure count).
    private func recordCaptureSuccess(for item: MenuBarItem) {
        let recovered = failedCapturesLock.withLock { dict in
            dict.removeValue(forKey: item.tag)
        }
        if let existing = recovered, existing.failureCount >= 2 {
            MenuBarItemImageCache.diagLog.info(
                "Item recovered after \(existing.failureCount) previous failures: \(item.logString)"
            )
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
        let candidates: [(tag: MenuBarItemTag, timestamp: UInt64)] = if excludedTags.isEmpty {
            images.keys.map { ($0, accessTimestamps[$0] ?? 0) }
        } else {
            images.keys
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
        if let image = images[tag], !image.isEffectivelyBlank {
            updateAccessOrder(for: tag)
            return image
        }
        // Fallback: match by namespace and title only (ignoring windowID).
        // This covers disk-loaded entries that were stored without a windowID.
        if !tag.isSystemItem,
           let entry = images.first(where: { $0.key.matchesIgnoringWindowID(tag) }),
           !entry.value.isEffectivelyBlank
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
        let failedCleared = failedCapturesLock.withLock { dict in
            let count = dict.count
            dict.removeAll()
            return count
        }
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
        let (failedCount, blacklistedCount) = failedCapturesLock.withLock { dict in
            (dict.count, dict.values.count(where: { $0.failureCount >= Self.maxFailuresBeforeBlacklist }))
        }

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

    /// Resolves which requested sections currently have live menu-bar pixels
    /// available for capture. macOS 27 physically removes concealed items from
    /// MenuBarAgent, but temporarily revealed sections can and should be
    /// captured so their real glyphs remain cached after concealment resumes.
    static nonisolated func capturableSections(
        from requestedSections: [MenuBarSection.Name],
        usesVisibilityRestrictions: Bool,
        revealedSection: MenuBarSection.Name?
    ) -> [MenuBarSection.Name] {
        let backend: any MenuBarBackend = usesVisibilityRestrictions
            ? AssertionMenuBarBackend()
            : LegacyMenuBarBackend()
        return backend.capturableSections(
            from: requestedSections,
            revealedSection: revealedSection
        )
    }

    /// Updates the cache for the given sections, without checking whether
    /// caching is necessary.
    @MainActor
    func updateCacheWithoutChecks(sections: [MenuBarSection.Name]) async {
        guard let appState else {
            MenuBarItemImageCache.diagLog.warning("updateCacheWithoutChecks: appState is nil, aborting")
            return
        }

        let hasScreenRecording = appState.hasPermission(.screenRecording)
        guard hasScreenRecording else {
            MenuBarItemImageCache.diagLog.debug("updateCacheWithoutChecks: no screen recording permission, aborting")
            return
        }

        guard let displayID = appState.itemManager.itemCache.displayID else {
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

        // Concealed macOS 27 sections have only stale snapshot bounds, so crop
        // them only while SimpleItemHider has actually revealed their live AX
        // elements. Their last-good captures remain cached after they hide.
        let sectionsToCapture = MenuBarBackendFactory.current.capturableSections(
            from: sections,
            revealedSection: appState.menuBarManager.simpleItemHider?.revealedSection
        )

        MenuBarItemImageCache.diagLog.notice("updateCacheWithoutChecks: displayID=\(screen.displayID) backingScaleFactor=\(Double(scale)) hasNotch=\(screen.hasNotch) menuBarHeight=\(Double(screen.getMenuBarHeightEstimate())) sections=\(sectionsToCapture.map(\.logString))")
        var newImages = [MenuBarItemTag: CapturedImage]()

        for section in sectionsToCapture {
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

        // Do NOT check Task.isCancelled here: if any captures succeeded (e.g.
        // the prewarm completed its hidden-section AX crop), we must apply them
        // even when the parent task was cancelled mid-settle (user re-clicked the
        // IceBar before the settle delay expired). The per-section guard above
        // already prevents starting new captures when cancelled.
        guard !newImages.isEmpty else { return }

        // Get the set of valid item tags from all sections to clean up stale entries
        let allValidTags = Set(
            appState.itemManager.itemCache.managedItems.map(\.tag)
        )

        // Plus the tags of items the hider has assigned (their snapshots). A
        // concealed item can briefly fall out of `managedItems` between conceal
        // and the snapshot re-add; without this it would lose its last-good icon
        // here and show a blank Hidden slot after a visible→hidden move.
        let assignedSnapshotTags = appState.menuBarManager.simpleItemHider?.assignedSnapshotTags ?? []

        await MainActor.run { [newImages, allValidTags, assignedSnapshotTags] in
            let beforeCount = images.count

            // Tags with recent capture failures should keep their cached images
            // even if the item temporarily left the item cache (e.g. a transient
            // menu bar item whose window briefly disappeared). This prevents
            // the IceBar and search from showing empty icons while the item's
            // app is still running.
            let recentlyFailedTags = failedCapturesLock.withLock { Set($0.keys) }

            // Remove images for items that no longer exist in the item cache,
            // but preserve images for items that have recent capture failures
            // (they may reappear shortly with a new window ID) and for
            // hider-assigned items (concealed items mid-re-add).
            // Use matchesIgnoringWindowID for non-system items so disk-loaded
            // entries are not incorrectly evicted when their windowID is nil.
            images = images.filter { key, _ in
                if key.isSystemItem {
                    return allValidTags.contains(key)
                        || recentlyFailedTags.contains(key)
                        || assignedSnapshotTags.contains(key)
                }
                return containsTagMatchingIgnoringWindowID(allValidTags, target: key) ||
                    containsTagMatchingIgnoringWindowID(recentlyFailedTags, target: key) ||
                    containsTagMatchingIgnoringWindowID(assignedSnapshotTags, target: key)
            }

            // Additional cleanup must preserve the same transiently valid sets
            // as the filter above. Otherwise an assigned snapshot can survive
            // that filter and then be evicted immediately here while its live
            // item is between concealment and cache re-addition.
            _ = validateAndCleanupInvalidEntries(
                preserving: recentlyFailedTags.union(assignedSnapshotTags)
            )

            // Mark all newly captured images as most recently used
            for tag in newImages.keys {
                accessCounter += 1
                accessTimestamps[tag] = accessCounter
            }

            // Remove old entries whose (namespace, title, instanceIndex) matches a
            // new entry but with a different windowID. After a monitor reconnect,
            // items may get new windowIDs, causing duplicate cache entries for the
            // same logical item. Keep only the latest capture (newImages wins).
            let newKeysSet = Set(newImages.keys)
            let staleKeys = images.keys.filter { oldKey in
                guard !oldKey.isSystemItem, !newKeysSet.contains(oldKey) else {
                    return false
                }
                return containsTagMatchingIgnoringWindowID(newKeysSet, target: oldKey)
            }
            for tag in staleKeys {
                images.removeValue(forKey: tag)
                accessTimestamps.removeValue(forKey: tag)
            }

            // Merge in the new images
            images.merge(newImages) { _, new in new }

            // Enforce cache size limit using LRU eviction, but never evict
            // items that still exist in the menu bar (valid item tags).
            // This prevents thrashing the cache for visible items when
            // many transient items come and go (e.g. monitor hotplug).
            if images.count > Self.maxCacheSize {
                let protectedTags = allValidTags
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

    /// Restoration action after temporarily revealing a section for prewarm capture.
    enum PrewarmRevealRestorationAction: Equatable {
        case hide
        case noOp
        case show(MenuBarSection.Name)

        static func resolve(
            previous: MenuBarSection.Name?,
            currentAfterShow: MenuBarSection.Name?
        ) -> PrewarmRevealRestorationAction {
            if previous == nil {
                return .hide
            }
            if previous == currentAfterShow {
                return .noOp
            }
            if let previous {
                return .show(previous)
            }
            return .noOp
        }
    }

    /// Whether prewarm should recapture an item given its cached image state.
    static func prewarmNeedsCapture(
        cachedImage: CapturedImage?,
        wouldAttemptCapture: Bool
    ) -> Bool {
        guard wouldAttemptCapture else { return false }
        guard let cachedImage, !cachedImage.isEffectivelyBlank else { return true }
        return false
    }

    /// Briefly reveals concealed macOS 27 sections so their live glyphs can be
    /// captured before the assertion hides them again.
    @available(macOS 27, *)
    @MainActor
    func prewarmConcealedImagesMacOS27(
        sections requestedSections: [MenuBarSection.Name],
        onlyMissingImages: Bool = true
    ) async {
        guard appState?.menuBarManager.simpleItemHider != nil else {
            return
        }

        let sections = requestedSections.reduce(into: [MenuBarSection.Name]()) { result, section in
            guard section != .visible, !result.contains(section) else { return }
            result.append(section)
        }

        // Batch prewarm when .alwaysHidden is requested: revealing .alwaysHidden
        // also reveals .hidden items, so capture all sections in a single
        // restriction toggle instead of two (which otherwise causes visible
        // flickering as items appear and disappear twice).
        if sections.contains(.alwaysHidden) {
            await Task { @MainActor [weak self, weak appState] in
                guard let self, let appState, let hider = appState.menuBarManager.simpleItemHider else {
                    return
                }

                let sectionsToCapture: [MenuBarSection.Name] = if onlyMissingImages {
                    sections.filter { section in
                        let sectionItems = appState.itemManager.itemCache[section]
                        guard !sectionItems.isEmpty else { return false }
                        return sectionItems.contains { item in
                            Self.prewarmNeedsCapture(
                                cachedImage: self.images[item.tag],
                                wouldAttemptCapture: self.wouldAttemptCapture(of: item)
                            )
                        }
                    }
                } else {
                    sections.filter { section in
                        !appState.itemManager.itemCache[section].isEmpty
                    }
                }
                guard !sectionsToCapture.isEmpty else { return }
                guard !Task.isCancelled else { return }

                let previousRevealedSection = hider.revealedSection
                hider.show(.alwaysHidden, reconcileBoundary: false)
                defer {
                    switch Self.PrewarmRevealRestorationAction.resolve(
                        previous: previousRevealedSection,
                        currentAfterShow: hider.revealedSection
                    ) {
                    case .hide:
                        hider.hideRevealedSections()
                    case .noOp:
                        break
                    case let .show(section):
                        hider.show(section, reconcileBoundary: false)
                    }
                }
                guard hider.revealedSection == .alwaysHidden else {
                    return
                }
                try? await Task.detached {
                    try await Task.sleep(for: Constants.MenuBarTuning.iceBarCaptureSettle)
                }.value
                await self.updateCacheWithoutChecks(sections: sectionsToCapture)
            }.value
            return
        }

        for section in sections {
            await Task { @MainActor [weak self, weak appState] in
                guard let self, let appState, let hider = appState.menuBarManager.simpleItemHider else {
                    return
                }

                let sectionItems = appState.itemManager.itemCache[section]
                guard !sectionItems.isEmpty else { return }

                let itemsToCapture = sectionItems.filter { item in
                    !onlyMissingImages || Self.prewarmNeedsCapture(
                        cachedImage: self.image(for: item.tag),
                        wouldAttemptCapture: self.wouldAttemptCapture(of: item)
                    )
                }
                guard !itemsToCapture.isEmpty else { return }

                guard !Task.isCancelled else {
                    MenuBarItemImageCache.diagLog.debug(
                        "prewarmConcealedImagesMacOS27: capture cancelled before start for \(section.logString)"
                    )
                    return
                }

                if appState.settings.advanced.enableExperimentalOverflowPrevention {
                    // Per-item precise reveal: capture one concealed glyph at a
                    // time instead of the whole section, so a dynamic-title
                    // neighbor (e.g. iStat Menus) doesn't flicker or vanish
                    // while this item's real glyph is being captured.
                    let displayID = appState.itemManager.itemCache.displayID
                        ?? Bridging.getActiveMenuBarDisplayID()
                        ?? CGMainDisplayID()
                    let scale = NSScreen.screens.first { $0.displayID == displayID }?.backingScaleFactor
                        ?? NSScreen.main?.backingScaleFactor
                        ?? 2

                    for item in itemsToCapture {
                        guard !Task.isCancelled else { return }

                        hider.revealItemTemporarily(item.uniqueIdentifier)
                        defer {
                            hider.concealTemporarilyRevealedItem(item.uniqueIdentifier)
                        }

                        try? await Task.sleep(for: Constants.MenuBarTuning.layoutPrewarmCaptureSettle)

                        let liveItems = await MenuBarItem.getMenuBarItems(
                            on: displayID,
                            option: [.onScreen, .activeSpace]
                        )
                        guard let liveItem = liveItems.first(where: {
                            $0.hasSameIdentity(as: item) || $0.uniqueIdentifier == item.uniqueIdentifier
                        }) else {
                            continue
                        }

                        // Capture against the resolved displayID directly rather
                        // than captureImages(appState:), which re-resolves the
                        // "active" display internally and can crop bounds from
                        // one display against another display's hosting-window
                        // screenshot on multi-display setups.
                        let captureResult = await self.axBoundsCapture(
                            [(item: liveItem, bounds: liveItem.bounds)],
                            scale: scale,
                            displayID: displayID
                        )
                        guard let image = captureResult.images[liveItem.tag] else {
                            continue
                        }
                        if let cachedImage = self.images[item.tag],
                           image.scaledSize.width < cachedImage.scaledSize.width * 0.75
                        {
                            continue
                        }

                        if !CapturedImage.isVisuallyEqual(self.images[item.tag], image) {
                            self.images[item.tag] = image
                            self.accessCounter += 1
                            self.accessTimestamps[item.tag] = self.accessCounter
                        }
                    }
                    self.saveToDisk()
                } else {
                    let previousRevealedSection = hider.revealedSection
                    hider.show(section, reconcileBoundary: false)
                    defer {
                        switch Self.PrewarmRevealRestorationAction.resolve(
                            previous: previousRevealedSection,
                            currentAfterShow: hider.revealedSection
                        ) {
                        case .hide:
                            hider.hideRevealedSections()
                        case .noOp:
                            break
                        case let .show(section):
                            hider.show(section, reconcileBoundary: false)
                        }
                    }
                    guard hider.revealedSection == section else {
                        MenuBarItemImageCache.diagLog.debug(
                            "prewarmConcealedImagesMacOS27: section not revealed for \(section.logString)"
                        )
                        return
                    }
                    try? await Task.detached {
                        try await Task.sleep(for: Constants.MenuBarTuning.iceBarCaptureSettle)
                    }.value
                    await self.updateCacheWithoutChecks(sections: [section])
                }
            }.value
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

        // Use provided snapshot or construct one in a single MainActor hop
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

        MenuBarItemImageCache.diagLog.debug("updateCache: proceeding with cache update for \(sections.count) sections (iceBar=\(navSnapshot.isIceBarPresented), search=\(navSnapshot.isSearchPresented), background=\(allowBackgroundCapture))")
        await updateCacheWithoutChecks(sections: sections)
    }

    /// Updates the cache for all sections, if necessary.
    @MainActor
    func updateCache(nav: NavigationStateSnapshot? = nil) async {
        guard let appState else {
            return
        }

        // Use provided snapshot or construct one in a single MainActor hop
        let navSnapshot: NavigationStateSnapshot = if let nav {
            nav
        } else {
            await MainActor.run {
                makeNavigationStateSnapshot()
            }
        }

        var sectionsNeedingDisplay = [MenuBarSection.Name]()

        if navSnapshot.isSearchPresented {
            sectionsNeedingDisplay = [.visible]
        } else if navSnapshot.isSettingsPresented {
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

    /// Forces an immediate capture for the visible layout/search/IceBar consumer
    /// after a deliberate reorder has settled.
    ///
    /// The periodic live-refresh loop honors a recent-move guard (it skips ticks
    /// within ~2 s of a move) and the capture-invalidation key ignores position,
    /// so a pure reorder leaves the layout UI showing the pre-reorder screenshot
    /// until the next nav change. The reorder caller invokes this once the bar
    /// has re-sorted, so `skipRecentMoveCheck` is safe here. The visible-consumer
    /// guard inside ``updateCache(sections:skipRecentMoveCheck:allowBackgroundCapture:nav:)``
    /// keeps this free when no capture consumer is on screen.
    @MainActor
    func refreshAfterReorder() async {
        guard let appState else {
            return
        }
        let navSnapshot = makeNavigationStateSnapshot()

        var sectionsNeedingDisplay = [MenuBarSection.Name]()
        if navSnapshot.isSearchPresented {
            sectionsNeedingDisplay = [.visible]
        } else if navSnapshot.isSettingsPresented {
            sectionsNeedingDisplay = MenuBarSection.Name.allCases
        } else if navSnapshot.isIceBarPresented, let section = appState.menuBarManager.iceBarPanel
            .currentSection
        {
            sectionsNeedingDisplay.append(section)
        }

        guard !sectionsNeedingDisplay.isEmpty else {
            return
        }

        await updateCache(
            sections: sectionsNeedingDisplay,
            skipRecentMoveCheck: true,
            nav: navSnapshot
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
        failedCapturesLock.withLock { $0.removeAll() }
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
