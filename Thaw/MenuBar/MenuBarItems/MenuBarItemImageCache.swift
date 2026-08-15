//
//  MenuBarItemImageCache.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
import Cocoa
import Collections
import Combine
import Observation
import os.lock

/// Cache for menu bar item images.
@MainActor
@Observable
final class MenuBarItemImageCache: @unchecked Sendable {
    private static nonisolated let diagLog = DiagLog(category: "MenuBarItemImageCache")

    nonisolated struct DisplayResolution: Equatable {
        let displayID: CGDirectDisplayID
        let usedFallback: Bool
    }

    static nonisolated func resolveDisplayID(
        preferredDisplayID: CGDirectDisplayID?,
        availableDisplayIDs: [CGDirectDisplayID],
        activeMenuBarDisplayID: CGDirectDisplayID?,
        mainDisplayID: CGDirectDisplayID
    ) -> DisplayResolution? {
        guard !availableDisplayIDs.isEmpty else {
            return nil
        }

        if let preferredDisplayID, availableDisplayIDs.contains(preferredDisplayID) {
            return DisplayResolution(displayID: preferredDisplayID, usedFallback: false)
        }

        if let activeMenuBarDisplayID, availableDisplayIDs.contains(activeMenuBarDisplayID) {
            return DisplayResolution(
                displayID: activeMenuBarDisplayID,
                usedFallback: preferredDisplayID != nil
            )
        }

        if availableDisplayIDs.contains(mainDisplayID) {
            return DisplayResolution(
                displayID: mainDisplayID,
                usedFallback: preferredDisplayID != nil
            )
        }

        return DisplayResolution(
            displayID: availableDisplayIDs[0],
            usedFallback: preferredDisplayID != nil
        )
    }

    @MainActor
    private static func resolveScreen(
        preferredDisplayID: CGDirectDisplayID?,
        screens: [NSScreen] = NSScreen.screens
    ) -> (screen: NSScreen, usedFallback: Bool)? {
        guard let resolution = resolveDisplayID(
            preferredDisplayID: preferredDisplayID,
            availableDisplayIDs: screens.map(\.displayID),
            activeMenuBarDisplayID: Bridging.getActiveMenuBarDisplayID(),
            mainDisplayID: CGMainDisplayID()
        ) else {
            return nil
        }

        guard let screen = screens.first(where: { $0.displayID == resolution.displayID }) else {
            return nil
        }

        return (screen, resolution.usedFallback)
    }

    /// A representation of a captured menu bar item image.
    nonisolated struct CapturedImage: Hashable {
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
        /// Pointer-equal `CGImage`s are a fast path, but scale still has to match.
        /// Otherwise compare dimensions and pixel data.
        static func isVisuallyEqual(_ old: CapturedImage?, _ new: CapturedImage?) -> Bool {
            guard let old, let new else { return old == nil && new == nil }
            if old.cgImage === new.cgImage {
                return old.scale == new.scale
            }
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
    private(set) var images = [MenuBarItemTag: CapturedImage]()

    /// Memoized results of ``trimmedImage(for:)``, keyed by tag, each paired
    /// with the `CGImage` it was derived from so a recapture invalidates it.
    ///
    /// Deliberately not observable: this is derived data, and writing it from
    /// inside a SwiftUI body — which is exactly where it is filled — must not
    /// invalidate the view that just read it.
    @ObservationIgnored private var trimmedImages = [MenuBarItemTag: (source: CGImage, image: NSImage)]()

    /// Maximum number of images to cache to prevent memory growth
    private static let maxCacheSize = 200

    /// LRU tracking from least to most recently used.
    /// Cache reads update this from SwiftUI bodies, so it must not invalidate them.
    @ObservationIgnored private var accessOrder = OrderedSet<MenuBarItemTag>()

    /// Serializes every WindowServer capture path, including explicit cache
    /// rebuilds and the live refresh loop.
    private let captureSemaphore = SimpleSemaphore(value: 1)

    init(images: [MenuBarItemTag: CapturedImage] = [:]) {
        self.images = images
        accessOrder = OrderedSet(images.keys)
    }

    /// Failed capture tracking to skip repeatedly failing items
    private struct FailedCapture: Hashable {
        let tag: MenuBarItemTag
        let failureCount: Int
        let lastFailureTime: Date
    }

    private let failedCapturesLock = OSAllocatedUnfairLock<[MenuBarItemTag: FailedCapture]>(initialState: [:])

    /// Configuration for failed capture handling
    private static nonisolated let maxFailuresBeforeBlacklist = 3
    private static nonisolated let blacklistCooldownSeconds: TimeInterval = 30 // 30 seconds

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

    /// Task observing `AdvancedSettings.iconRefreshInterval`, which is
    /// `@Observable` rather than a Combine `ObservableObject`.
    private var iconRefreshIntervalObservationTask: Task<Void, Never>?

    /// Task observing `AppNavigationState`'s properties (wave 3), which is
    /// `@Observable` rather than a Combine `ObservableObject`.
    private var navigationStateObservationTask: Task<Void, Never>?

    /// Task observing `menuBarManager.averageColorInfo` (wave 3), which is
    /// `@Observable` rather than a Combine `ObservableObject`. Bridges into
    /// `colorChangeSubject` so it can still participate in the
    /// `Publishers.MergeMany` below.
    private var averageColorInfoObservationTask: Task<Void, Never>?

    /// Bridges `averageColorInfoObservationTask`'s Observation-based updates
    /// into the Combine `Publishers.MergeMany` pipeline in
    /// `configureCancellables()`.
    private let colorChangeSubject = PassthroughSubject<Void, Never>()

    /// Task observing `itemManager.itemCache` (wave 4), which is
    /// `@Observable` rather than a Combine `ObservableObject`. Bridges into
    /// `itemCacheChangeSubject` so it can still participate in the
    /// `Publishers.MergeMany` below.
    private var itemCacheObservationTask: Task<Void, Never>?

    /// Bridges `itemCacheObservationTask`'s Observation-based updates into
    /// the Combine `Publishers.MergeMany` pipeline in
    /// `configureCancellables()`.
    private let itemCacheChangeSubject = PassthroughSubject<Void, Never>()

    private var memoryPressureSource: DispatchSourceMemoryPressure?

    /// The currently running cache update task, if any.
    private var currentUpdateTask: Task<Void, Never>?

    /// The currently running live-refresh task, if any.
    private var liveRefreshTask: Task<Void, Never>?

    /// Timestamp of the last Hidden-section capture.
    private var lastHiddenRefreshAt: ContinuousClock.Instant?

    /// Timestamp of the last Always Hidden-section capture.
    private var lastAlwaysHiddenRefreshAt: ContinuousClock.Instant?

    /// Timestamp of the last visible-section SCK capture, used to rate-limit
    /// the on-screen path the same way the offscreen one already is.
    private var lastSCKRefreshAt: ContinuousClock.Instant?

    /// Maximum icon refresh rate the UI may offer, in frames per second.
    ///
    /// The slider ceiling and the SCK / Hidden capture floor are the same
    /// number so they cannot drift apart. Always Hidden stays at 1 fps.
    nonisolated static let maxIconRefreshRate: Double = 30

    /// Minimum spacing enforced between visible-section SCK captures, in seconds.
    /// Reciprocal of ``maxIconRefreshRate``.
    nonisolated static let minIconRefreshInterval: TimeInterval = 1.0 / maxIconRefreshRate

    /// Tracks whether the MenuBarLayoutSettingsPane is currently open.
    /// Used to gate background cache prewarming so captures only occur while the
    /// user has the layout settings open, rather than staying stuck on for the
    /// remaining lifetime of the process after the first open (#759).
    private(set) var isSettingsPaneOpen = false

    /// Whether the per-item hotkey list in the Hotkeys settings pane is expanded.
    /// While collapsed, the pane has no visible item-icon consumer, so the live
    /// capture loop stays off rather than paying the off-screen SkyLight capture
    /// cost for items the user cannot see.
    private(set) var isItemHotkeyListExpanded = false {
        didSet {
            guard oldValue != isItemHotkeyListExpanded else { return }
            startLiveRefreshIfNeeded()
        }
    }

    /// Updates isItemHotkeyListExpanded from the Hotkeys settings UI.
    func setItemHotkeyListExpanded(_ expanded: Bool) {
        guard isItemHotkeyListExpanded != expanded else {
            return
        }
        isItemHotkeyListExpanded = expanded
    }

    @MainActor
    deinit {
        memoryPressureSource?.cancel()
        currentUpdateTask?.cancel()
        liveRefreshTask?.cancel()
        iconRefreshIntervalObservationTask?.cancel()
        navigationStateObservationTask?.cancel()
        averageColorInfoObservationTask?.cancel()
        itemCacheObservationTask?.cancel()
    }

    // MARK: Setup

    /// Sets up the cache.
    @MainActor
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()

        // Try to load cached images from disk
        loadFromDisk()

        // Only prewarm if a visible consumer exists at setup time.
        // Background prewarming is gated by isSettingsPaneOpen.
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
        isSettingsPaneOpen = true
    }

    /// Marks that the MenuBarLayoutSettingsPane has been closed.
    /// Call this from the pane's onDisappear to stop background cache prewarming
    /// once the pane is no longer visible.
    @MainActor
    func markSettingsPaneClosed() {
        isSettingsPaneOpen = false
    }

    // MARK: Disk Persistence

    /// Path to the cache file in Caches directory.
    private static var cacheFileURL: URL? {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return cacheDir?.appendingPathComponent("com.stonerl.thaw/imageCache.json")
    }

    /// Maximum age of disk cache before it's considered stale (30 seconds).
    private static nonisolated let maxCacheAgeSeconds: TimeInterval = 30

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

            // `menuBarManager` is now `@Observable` (wave 3), so it no longer
            // has an `$averageColorInfo` publisher. `colorChangeSubject` is
            // fed by `averageColorInfoObservationTask` (started below) and
            // bridges those updates back into this Combine merge.
            let colorChangePublisher: AnyPublisher<Void, Never> = colorChangeSubject
                .eraseToAnyPublisher()

            averageColorInfoObservationTask?.cancel()
            averageColorInfoObservationTask = Task { [weak self, weak appState] in
                var previous: MenuBarAverageColorInfo?
                let changes = Observations { appState?.menuBarManager.averageColorInfo }
                for await info in changes {
                    guard let self else { return }
                    guard info != previous else { continue }
                    previous = info
                    self.colorChangeSubject.send(())
                }
            }

            // `itemManager` is now `@Observable` (wave 4), so it no longer
            // has a `$itemCache` publisher. `itemCacheChangeSubject` is fed
            // by `itemCacheObservationTask` (started below) and bridges
            // those updates back into this Combine merge.
            let itemCacheChangePublisher: AnyPublisher<Void, Never> = itemCacheChangeSubject
                .eraseToAnyPublisher()

            itemCacheObservationTask?.cancel()
            itemCacheObservationTask = Task { [weak self, weak appState] in
                var previous: MenuBarItemManager.ItemCache?
                let changes = Observations { appState?.itemManager.itemCache }
                for await cache in changes {
                    guard let self else { return }
                    guard cache != previous else { continue }
                    previous = cache
                    self.itemCacheChangeSubject.send(())
                }
            }

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
                // Only trigger capture if a visible consumer exists or the settings pane
                // is currently open (itemCacheChangePublisher may indicate
                // new items that the layout pane will need).
                let nav = self.makeNavigationStateSnapshot()
                let hasVisible = self.hasVisibleCaptureConsumer(nav: nav)
                let settingsOpen = self.isSettingsPaneOpen
                guard hasVisible || settingsOpen else {
                    return
                }
                self.currentUpdateTask?.cancel()
                self.currentUpdateTask = Task { [weak self, settingsOpen] in
                    await self?.refreshVisibleConsumersOrPrewarmLayoutCache(
                        allowBackgroundCapture: settingsOpen
                    )
                }
            }
            .store(in: &c)

            // Observe navigation state changes to start/stop live refresh.
            // `AppNavigationState` is `@Observable` (wave 3) rather than a
            // Combine `ObservableObject`, so this is observed via the
            // `Observations` async sequence instead of its old
            // `$isIceBarPresented`/etc. projections. The original pipeline
            // debounced 50ms; since `startLiveRefreshIfNeeded()` is itself
            // idempotent (guards internally against redundant starts), the
            // debounce is dropped in favor of firing directly on each change.
            navigationStateObservationTask = Task { @MainActor [weak self, navigationState = appState.navigationState] in
                let changes = Observations {
                    (
                        navigationState.isIceBarPresented,
                        navigationState.isSearchPresented,
                        navigationState.isSettingsPresented,
                        navigationState.settingsNavigationIdentifier,
                        navigationState.isAppFrontmost
                    )
                }
                for await _ in changes {
                    guard let self else { return }
                    self.startLiveRefreshIfNeeded()
                }
            }

            // Start/stop the live refresh when the Hotkeys pane's per-item list
            // is expanded or collapsed, since that gates its capture consumer.
            // Replaced by `isItemHotkeyListExpanded`'s `didSet` above now
            // that this class is @Observable (no more `$isItemHotkeyListExpanded`
            // Combine projection to subscribe to).

            // Restart the live refresh loop when the icon refresh interval
            // changes. `AdvancedSettings` is `@Observable` rather than a
            // Combine `ObservableObject`, so this is observed via the
            // `Observations` async sequence instead of `$iconRefreshInterval`.
            let advancedSettings = appState.settings.advanced
            iconRefreshIntervalObservationTask = Task { @MainActor [weak self] in
                let changes = Observations { advancedSettings.iconRefreshInterval }
                for await _ in changes {
                    guard let self else { return }
                    guard self.liveRefreshTask != nil else { continue }
                    self.liveRefreshTask?.cancel()
                    self.liveRefreshTask = nil
                    self.startLiveRefreshIfNeeded()
                }
            }
        }

        cancellables = c
    }

    // MARK: Live Refresh

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

    /// Pure gating decision for whether a background (offscreen-inclusive) capture
    /// cycle should proceed: either a visible consumer needs it, or the caller
    /// explicitly requested a background capture while the layout settings pane
    /// is currently open. Extracted for unit testing (#759).
    static nonisolated func shouldAllowBackgroundCapture(
        hasVisibleConsumer: Bool,
        allowBackgroundCapture: Bool,
        isSettingsPaneOpen: Bool
    ) -> Bool {
        hasVisibleConsumer || (allowBackgroundCapture && isSettingsPaneOpen)
    }

    /// Refreshes the cache for currently visible consumers, or keeps a warm
    /// background snapshot ready for the layout settings pane when no consumer
    /// is visible.
    private func refreshVisibleConsumersOrPrewarmLayoutCache(allowBackgroundCapture: Bool = false) async {
        guard appState != nil else {
            return
        }

        // Batch all navigation state reads into single MainActor hop
        let nav = await MainActor.run {
            makeNavigationStateSnapshot()
        }

        let hasVisibleConsumer = hasVisibleCaptureConsumer(nav: nav)

        // Early-return unless a visible consumer exists or background capture is explicitly allowed.
        // Background capture is gated by isSettingsPaneOpen to avoid unnecessary full-screen
        // captures once the user has closed the layout settings pane (#759).
        guard Self.shouldAllowBackgroundCapture(
            hasVisibleConsumer: hasVisibleConsumer,
            allowBackgroundCapture: allowBackgroundCapture,
            isSettingsPaneOpen: isSettingsPaneOpen
        ) else {
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
                lastSCKRefreshAt = nil
                lastHiddenRefreshAt = nil
                lastAlwaysHiddenRefreshAt = nil
                self.liveRefreshTask = Task { [weak self] in
                    guard let self else { return }
                    await self.runLiveRefreshLoop()
                }
            } else {
                guard let task = self.liveRefreshTask else { return }
                MenuBarItemImageCache.diagLog.debug("Stopping live refresh")
                self.liveRefreshTask = nil
                task.cancel()
                await task.value
                guard self.liveRefreshTask == nil else { return }
                await MenuBarCaptureService.Connection.shared.recycle()
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
            let interval = appState.settings.advanced.iconRefreshInterval
            guard interval > 0 else {
                try? await Task.sleep(for: .seconds(1))
                continue
            }

            let nav = appState.navigationState

            let preferredDisplayID = appState.itemManager.itemCache.displayID
            guard let resolvedScreen = Self.resolveScreen(preferredDisplayID: preferredDisplayID) else {
                MenuBarItemImageCache.diagLog.warning("liveRefresh: no connected screens available, skipping")
                try? await Task.sleep(for: .seconds(max(interval, Self.minIconRefreshInterval)))
                continue
            }
            let screen = resolvedScreen.screen
            if resolvedScreen.usedFallback, let preferredDisplayID {
                MenuBarItemImageCache.diagLog.warning(
                    "liveRefresh: cached displayID \(preferredDisplayID) is not connected; using displayID \(screen.displayID)"
                )
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
            if nav.isSearchPresented || isLayoutPane || isHotkeyListVisible {
                if nav.isSearchPresented, !isLayoutPane, !isHotkeyListVisible {
                    // Search is the only consumer here that can be told to
                    // leave whole sections out of its results; capturing icons
                    // for rows it will never render is pure waste. The layout
                    // pane and the hotkey list always show every section, so
                    // they keep the unfiltered set.
                    let advanced = appState.settings.advanced
                    sections = MenuBarSection.Name.allCases.filter { name in
                        switch name {
                        case .visible: advanced.searchIncludeVisible
                        case .hidden: advanced.searchIncludeHidden
                        case .alwaysHidden: advanced.searchIncludeAlwaysHidden
                        }
                    }
                } else {
                    sections = MenuBarSection.Name.allCases
                }
            } else if nav.isIceBarPresented,
                      let current = appState.menuBarManager.iceBarPanel.currentSection
            {
                sections = [current]
            } else {
                try? await Task.sleep(for: .milliseconds(50))
                continue
            }

            if appState.itemManager.lastMoveOperationOccurred(within: .seconds(2))
                || appState.itemManager.isResettingLayout
            {
                try? await Task.sleep(for: .seconds(max(interval, Self.minIconRefreshInterval)))
                continue
            }

            let scale = screen.backingScaleFactor
            let now = ContinuousClock.now
            var nextWake = now + .seconds(max(interval, Self.minIconRefreshInterval))

            var hiddenItems = [MenuBarItem]()
            var alwaysHiddenItems = [MenuBarItem]()

            for section in sections {
                let items = appState.itemManager.itemCache.managedItems(for: section)
                guard !items.isEmpty else { continue }
                guard let sectionInterval = MenuBarLiveRefreshPolicy.refreshInterval(
                    for: section,
                    target: interval
                ) else { continue }
                let duration = Duration.seconds(sectionInterval)

                switch section {
                case .visible:
                    if MenuBarLiveRefreshPolicy.isDue(
                        lastCaptureAt: lastSCKRefreshAt,
                        now: now,
                        interval: duration
                    ) {
                        lastSCKRefreshAt = now
                        MenuBarItemImageCache.diagLog.debug(
                            "liveRefresh (SCK): section=\(section.logString) items=\(items.count)"
                        )
                        await withCapturePermit {
                            await refreshImages(of: items, scale: scale, viaSCK: true)
                        }
                    }
                    nextWake = min(
                        nextWake,
                        MenuBarLiveRefreshPolicy.nextDeadline(
                            capturedAt: lastSCKRefreshAt ?? now,
                            interval: duration,
                            now: ContinuousClock.now
                        )
                    )
                case .hidden:
                    hiddenItems = items
                case .alwaysHidden:
                    alwaysHiddenItems = items
                }
            }

            // One offscreen request in flight. Always Hidden goes first when
            // both are due so Hidden at 30 fps cannot starve its 1 fps slot.
            let hiddenInterval = MenuBarLiveRefreshPolicy.refreshInterval(for: .hidden, target: interval)
            let alwaysInterval = MenuBarLiveRefreshPolicy.refreshInterval(for: .alwaysHidden, target: interval)
            let hiddenDue = !hiddenItems.isEmpty
                && hiddenInterval != nil
                && MenuBarLiveRefreshPolicy.isDue(
                    lastCaptureAt: lastHiddenRefreshAt,
                    now: now,
                    interval: .seconds(hiddenInterval ?? interval)
                )
            let alwaysDue = !alwaysHiddenItems.isEmpty
                && alwaysInterval != nil
                && MenuBarLiveRefreshPolicy.isDue(
                    lastCaptureAt: lastAlwaysHiddenRefreshAt,
                    now: now,
                    interval: .seconds(alwaysInterval ?? 1)
                )

            switch MenuBarLiveRefreshPolicy.nextOffscreenSection(
                hiddenDue: hiddenDue,
                alwaysHiddenDue: alwaysDue
            ) {
            case .hidden:
                lastHiddenRefreshAt = now
                MenuBarItemImageCache.diagLog.debug("liveRefresh (capture): hidden items=\(hiddenItems.count)")
                await withCapturePermit {
                    await refreshImages(of: hiddenItems, scale: scale)
                }
            case .alwaysHidden:
                lastAlwaysHiddenRefreshAt = now
                MenuBarItemImageCache.diagLog.debug(
                    "liveRefresh (capture): alwaysHidden items=\(alwaysHiddenItems.count)"
                )
                await withCapturePermit {
                    await refreshImages(of: alwaysHiddenItems, scale: scale)
                }
            case .visible, nil:
                break
            }

            if let hiddenInterval, !hiddenItems.isEmpty {
                nextWake = min(
                    nextWake,
                    MenuBarLiveRefreshPolicy.nextDeadline(
                        capturedAt: lastHiddenRefreshAt ?? now,
                        interval: .seconds(hiddenInterval),
                        now: ContinuousClock.now
                    )
                )
            }
            if let alwaysInterval, !alwaysHiddenItems.isEmpty {
                nextWake = min(
                    nextWake,
                    MenuBarLiveRefreshPolicy.nextDeadline(
                        capturedAt: lastAlwaysHiddenRefreshAt ?? now,
                        interval: .seconds(alwaysInterval),
                        now: ContinuousClock.now
                    )
                )
            }

            let sleep = nextWake - ContinuousClock.now
            if sleep > .zero {
                try? await Task.sleep(for: sleep)
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

            let croppedImage = compositeImage.cropping(to: cropRect)?.detachedCopy()
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
    /// The scale a captured image was actually taken at, or `nil` when the
    /// image cannot be trusted at any scale.
    ///
    /// `expected` is the scale of the display Thaw resolved for the menu
    /// bar; the image's pixel width divided by the item's point width is the
    /// scale the window server actually captured at. Normally they agree.
    /// When they do not, the captured value is the truthful one — it is
    /// measured from the image in hand rather than inferred from a display
    /// that may not be the one ScreenCaptureKit chose.
    ///
    /// A derived scale that is not near a real backing scale factor means
    /// the bounds and the image describe different things (stale bounds, a
    /// window resized mid-capture), so there is no safe scale to cache
    /// under and the caller should drop the item. A missing icon is a
    /// recoverable degraded state; a wrongly-scaled one is not, because it
    /// gets cached and reused.
    ///
    /// - Parameters:
    ///   - imagePixelWidth: Width of the captured image, in pixels.
    ///   - boundsWidth: Width of the item's window, in points.
    ///   - expected: The scale of the display resolved for the menu bar.
    static nonisolated func resolvedScale(
        imagePixelWidth: Int,
        boundsWidth: CGFloat,
        expected: CGFloat
    ) -> CGFloat? {
        guard boundsWidth > 0, imagePixelWidth > 0, expected > 0 else {
            return nil
        }

        let derived = CGFloat(imagePixelWidth) / boundsWidth

        // Integer pixel widths make the derived value slightly noisy for
        // narrow items, so compare with a tolerance rather than exactly.
        if abs(derived - expected) <= scaleTolerance {
            return expected
        }

        // Only trust a disagreement that lands on a real backing scale
        // factor. Anything else is not a scale mismatch, it is bad input.
        return plausibleBackingScales.first { abs(derived - $0) <= scaleTolerance }
    }

    /// Backing scale factors macOS actually reports for a display.
    private static nonisolated let plausibleBackingScales: [CGFloat] = [1, 2, 3]

    /// How far a derived scale may sit from a candidate before it stops
    /// counting as that scale.
    private static nonisolated let scaleTolerance: CGFloat = 0.05

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

            // `scale` comes from the display Thaw believes owns the menu
            // bar, but ScreenCaptureKit captures at the scale of whichever
            // display it selects by frame intersection. On a mixed-scale
            // multi-display setup those disagree, and caching an image under
            // the wrong scale doubles every consumer's idea of its point
            // size — the oversized Layout rows in #851/#736.
            // `compositeCapture` and `refreshImages` both reject a
            // pixel/point mismatch; this path did not, and it is precisely
            // the fallback that runs after `compositeCapture` rejects one.
            guard let resolvedScale = MenuBarItemImageCache.resolvedScale(
                imagePixelWidth: image.width,
                boundsWidth: item.bounds.width,
                expected: scale
            ) else {
                MenuBarItemImageCache.diagLog.warning(
                    "individualCapture: implausible scale for \(item.logString) — \(image.width)px wide for bounds width \(item.bounds.width) at expected scale \(scale), excluding"
                )
                recordCaptureFailure(for: item)
                result.excluded.append(item)
                continue
            }

            if resolvedScale != scale {
                MenuBarItemImageCache.diagLog.warning(
                    "individualCapture: capture scale \(resolvedScale) differs from display scale \(scale) for \(item.logString); using the captured scale"
                )
            }

            // Record success and cache
            capturedCount += 1
            recordCaptureSuccess(for: item)
            result.images[item.tag] = CapturedImage(
                cgImage: image,
                scale: resolvedScale
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
        if !viaSCK {
            await refreshImagesFromCaptureService(items: items, scale: scale)
            return
        }

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
        let compositeImage = await ScreenCapture.captureWindowsAsync(
            with: windowIDs,
            option: captureOption
        )
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
            guard let image = compositeImage.cropping(to: cropRect)?.detachedCopy() else {
                continue
            }
            newImages[item.tag] = CapturedImage(cgImage: image, scale: scale)
        }

        guard !newImages.isEmpty, !Task.isCancelled else { return }
        await applyRefreshedImages(newImages)
    }

    /// Offscreen items go through the recyclable SkyLight helper so the
    /// per-call dictionary leak stays out of the UI process.
    private nonisolated func refreshImagesFromCaptureService(
        items: [MenuBarItem],
        scale: CGFloat
    ) async {
        let windowIDs = items.map(\.windowID)
        guard !windowIDs.isEmpty else { return }
        var storage = [CGWindowID: MenuBarItem]()
        for item in items {
            storage[item.windowID] = item
        }
        let frames = await MenuBarCaptureService.Connection.shared.capture(
            windowIDs: windowIDs,
            scale: scale,
            option: captureOption
        )
        guard !frames.isEmpty, !Task.isCancelled else { return }

        var newImages = [MenuBarItemTag: CapturedImage]()
        for frame in frames {
            guard let item = storage[frame.windowID],
                  let image = MenuBarCaptureService.makeImage(from: frame)
            else { continue }
            newImages[item.tag] = CapturedImage(cgImage: image, scale: CGFloat(frame.scale))
        }
        guard !newImages.isEmpty, !Task.isCancelled else { return }
        await applyRefreshedImages(newImages)
    }

    private func applyRefreshedImages(_ newImages: [MenuBarItemTag: CapturedImage]) {
        var updatedCount = 0
        for (tag, newImage) in newImages where !CapturedImage.isVisuallyEqual(images[tag], newImage) {
            images[tag] = newImage
            updateAccessOrder(for: tag)
            updatedCount += 1
        }
        if updatedCount > 0 {
            MenuBarItemImageCache.diagLog.debug(
                "refreshImages: ✓ updated \(updatedCount)/\(newImages.count) items (visually changed)"
            )
        }
    }

    /// Captures the images of the menu bar items in the given section and returns
    /// a dictionary containing the images, keyed by their menu bar item tags.
    private func captureImages(
        for section: MenuBarSection.Name,
        scale: CGFloat,
        appState: AppState
    ) async -> [MenuBarItemTag: CapturedImage] {
        let items = appState.itemManager.itemCache.managedItems(
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
    private nonisolated func shouldSkipCapture(for item: MenuBarItem) -> Bool {
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
    private nonisolated func recordCaptureFailure(for item: MenuBarItem) {
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
    private nonisolated func recordCaptureSuccess(for item: MenuBarItem) {
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
                accessOrder.remove(tag)
            }
            MenuBarItemImageCache.diagLog.info(
                "Memory pressure: Cleared \(tagsToRemove.count) items from cache"
            )
        }
    }

    /// Returns the `count` least recently used tags, sorted by access time (oldest first).
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

    // MARK: Cache Access

    /// Updates the access order for a given tag to mark it as most recently used.
    private func updateAccessOrder(for tag: MenuBarItemTag) {
        if accessOrder.contains(tag) {
            accessOrder.move(members: CollectionOfOne(tag), to: accessOrder.endIndex)
        } else {
            accessOrder.append(tag)
        }
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

    /// Returns the item's image with its transparent left and right margins
    /// trimmed off, ready to display at its captured scale.
    ///
    /// Memoized. Trimming allocates a `CGContext`, draws the image into it,
    /// and scans the result's alpha channel — cheap once, but its callers are
    /// SwiftUI bodies that re-evaluate for *every* row on every keystroke, so
    /// computing it on demand made the cost scale with item count × typing
    /// speed. The memo is keyed on the `CGImage` the trim came from, so a
    /// recapture (new icon state) still refreshes it.
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

    /// Returns the current cache size for monitoring purposes.
    var cacheSize: Int {
        images.count
    }

    /// Returns the number of tracked LRU entries for debugging.
    var lruEntryCount: Int {
        accessOrder.count
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

    // MARK: Update Cache

    /// Updates the cache for the given sections, without checking whether
    /// caching is necessary.
    @MainActor
    func updateCacheWithoutChecks(sections: [MenuBarSection.Name]) async {
        await withCapturePermit {
            await performCacheUpdateWithoutChecks(sections: sections)
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
    private func performCacheUpdateWithoutChecks(sections: [MenuBarSection.Name]) async {
        guard let appState else {
            MenuBarItemImageCache.diagLog.warning("updateCacheWithoutChecks: appState is nil, aborting")
            return
        }

        let hasScreenRecording = appState.hasPermission(.screenRecording)
        guard hasScreenRecording else {
            MenuBarItemImageCache.diagLog.debug("updateCacheWithoutChecks: no screen recording permission, aborting")
            return
        }

        let preferredDisplayID = appState.itemManager.itemCache.displayID
        guard let resolvedScreen = Self.resolveScreen(preferredDisplayID: preferredDisplayID) else {
            MenuBarItemImageCache.diagLog.warning("updateCacheWithoutChecks: no connected screens available, aborting")
            return
        }
        let screen = resolvedScreen.screen
        if resolvedScreen.usedFallback, let preferredDisplayID {
            MenuBarItemImageCache.diagLog.warning(
                "updateCacheWithoutChecks: cached displayID \(preferredDisplayID) is not connected; using displayID \(screen.displayID)"
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
        let allValidTags = Set(
            appState.itemManager.itemCache.managedItems.map(\.tag)
        )

        await MainActor.run { [newImages, allValidTags] in
            let beforeCount = images.count

            // Tags with recent capture failures should keep their cached images
            // even if the item temporarily left the item cache (e.g. a transient
            // menu bar item whose window briefly disappeared). This prevents
            // the IceBar and search from showing empty icons while the item's
            // app is still running.
            let recentlyFailedTags = failedCapturesLock.withLock { Set($0.keys) }

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
                updateAccessOrder(for: tag)
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
                accessOrder.remove(tag)
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
                    accessOrder.remove(tag)
                }

                if !tagsToRemove.isEmpty {
                    MenuBarItemImageCache.diagLog.info(
                        "LRU cache eviction: removed \(tagsToRemove.count) least recently used images (\(protectedTags.count) protected)"
                    )
                }
            }

            // Remove stale LRU entries for images that no longer exist.
            accessOrder = OrderedSet(accessOrder.lazy.filter { self.images[$0] != nil })

            let afterCount = images.count
            let finalAccessOrderCount = accessOrder.count
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
                !appState.itemManager.lastMoveOperationOccurred(
                    within: .seconds(1)
                )
            else {
                MenuBarItemImageCache.diagLog.debug(
                    "Skipping item image cache due to recent item movement"
                )
                return
            }

            // Skip updates during layout reset to prevent stale cache between passes
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

        // Use provided snapshot or construct one in a single MainActor hop
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

    /// Clears the images for the given section.
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
    }

    /// Clears all cached images and failure tracking.
    @MainActor
    func clearAll() {
        images.removeAll()
        accessOrder.removeAll()
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
