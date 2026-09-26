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
        let cgImage: CGImage

        /// The scale factor of the image at the time of capture.
        let scale: CGFloat

        /// Used to spot an item blinking for attention. Hashes pixel data, not
        /// CGImage identity; falls back to dimensions when there's no data.
        var fingerprint: Int {
            var hasher = Hasher()
            hasher.combine(cgImage.width)
            hasher.combine(cgImage.height)
            hasher.combine(scale)
            if let data = cgImage.dataProvider?.data {
                hasher.combine(data as Data)
            }
            return hasher.finalize()
        }

        /// The image's size, applying scale.
        var scaledSize: CGSize {
            CGSize(
                width: CGFloat(cgImage.width) / scale,
                height: CGFloat(cgImage.height) / scale
            )
        }

        /// The base image, converted to an NSImage and applying scale.
        var nsImage: NSImage {
            NSImage(cgImage: cgImage, size: scaledSize)
        }

        /// Returns whether two optional captured images have equivalent visual content.
        ///
        /// Pointer-equal CGImages are a fast path, but scale still has to match.
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

    private struct CaptureResult {
        var images = [MenuBarItemTag: CapturedImage]()

        /// The menu bar items excluded from the capture.
        var excluded = [MenuBarItem]()
    }

    /// Immutable input for a capture-helper batch that is safe to transfer
    /// from the main actor to the concurrent executor.
    private nonisolated struct IdentifierCaptureRequest: Sendable {
        let identifier: String
        let windowID: CGWindowID
    }

    /// The cached item images, keyed by their corresponding tags.
    private(set) var images = [MenuBarItemTag: CapturedImage]()

    /// Display the current ``images`` were captured for. The light/dark tint is
    /// baked into the capture, so another display's cache shows wrong colors.
    private(set) var lastCaptureDisplayID: CGDirectDisplayID?

    /// Per-display icon snapshots so switching screens can restore the correct
    /// light/dark tint immediately instead of flashing the previous screen.
    @ObservationIgnored
    private var imagesByDisplay = [CGDirectDisplayID: [MenuBarItemTag: CapturedImage]]()

    /// Tracks which items are blinking for attention.
    ///
    /// Not observable: it's fed on every capture. The verdict is published
    /// through tagsSeekingAttention instead.
    @ObservationIgnored private var attentionDetector = MenuBarItemAttentionDetector()

    /// The items currently asking for attention.
    private(set) var tagsSeekingAttention: Set<MenuBarItemTag> = []

    /// Item identifiers watched by enabled attention-seeking triggers.
    ///
    /// A set, not a flag: with no UI consumer the live loop captures only these.
    /// The global attention setting still samples every concealed item.
    @ObservationIgnored var attentionDetectionItemIdentifiers = Set<String>() {
        didSet {
            guard oldValue != attentionDetectionItemIdentifiers else { return }
            startLiveRefreshIfNeeded()
        }
    }

    /// Memoized results of trimmedImage(for:), keyed by tag, each paired
    /// with the CGImage it was derived from so a recapture invalidates it.
    ///
    /// Not observable: it's filled from SwiftUI bodies and must not invalidate them.
    @ObservationIgnored private var trimmedImages = [MenuBarItemTag: (source: CGImage, image: NSImage)]()

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

    private let queue = DispatchQueue(
        label: "MenuBarItemImageCache",
        qos: .background
    )

    private let captureOption: CGWindowImageOption = [
        .boundsIgnoreFraming, .bestResolution,
    ]

    private weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()

    /// AdvancedSettings is @Observable, not a Combine ObservableObject.
    private var iconRefreshIntervalObservationTask: Task<Void, Never>?

    /// AppNavigationState is @Observable, not a Combine ObservableObject.
    private var navigationStateObservationTask: Task<Void, Never>?

    /// Feeds colorChangeSubject so the @Observable averageColorInfo joins the Combine merge.
    private var averageColorInfoObservationTask: Task<Void, Never>?

    private let colorChangeSubject = PassthroughSubject<Void, Never>()

    /// Feeds itemCacheChangeSubject so the @Observable itemCache joins the Combine merge.
    private var itemCacheObservationTask: Task<Void, Never>?

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

    /// Whether a window's bounds can contribute to a composite capture.
    ///
    /// The capture APIs omit degenerate windows, so one would corrupt the slice geometry.
    static nonisolated func isCapturableBounds(_ bounds: CGRect) -> Bool {
        bounds.width > 0 && bounds.height > 0
    }

    /// Timestamp of the last visible-section SCK capture, used to rate-limit
    /// the on-screen path the same way the offscreen one already is.
    private var lastSCKRefreshAt: ContinuousClock.Instant?

    /// Maximum icon refresh rate the UI may offer, in frames per second.
    ///
    /// The slider ceiling and the SCK / Hidden capture floor are the same
    /// number so they cannot drift apart. Always Hidden stays at 1 fps.
    static nonisolated let maxIconRefreshRate: Double = 30

    /// Minimum spacing enforced between visible-section SCK captures, in seconds.
    /// Reciprocal of maxIconRefreshRate.
    static nonisolated let minIconRefreshInterval: TimeInterval = 1.0 / maxIconRefreshRate

    /// Gates background prewarming so it stops when the layout pane closes (#759).
    private(set) var isSettingsPaneOpen = false

    /// While collapsed nothing shows item icons, so the live capture loop stays off.
    private(set) var isItemHotkeyListExpanded = false {
        didSet {
            guard oldValue != isItemHotkeyListExpanded else { return }
            startLiveRefreshIfNeeded()
        }
    }

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

    @MainActor
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()

        loadFromDisk()

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

    /// Call from the layout pane's onAppear to enable background prewarming.
    @MainActor
    func markSettingsPaneOpened() {
        isSettingsPaneOpen = true
    }

    /// Call from the layout pane's onDisappear to stop background prewarming.
    @MainActor
    func markSettingsPaneClosed() {
        isSettingsPaneOpen = false
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

    @MainActor
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState {
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

            // Fed by averageColorInfoObservationTask, below.
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

            // Fed by itemCacheObservationTask, below.
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
                // The open layout pane may need new items, so it counts as a consumer.
                let nav = self.makeNavigationStateSnapshot()
                let hasVisible = self.hasVisibleCaptureConsumer(nav: nav)
                let settingsOpen = self.isSettingsPaneOpen && !nav.prefersAppIcon
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

            // Starts/stops live refresh. No debounce: startLiveRefreshIfNeeded() is idempotent.
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

            // Restart the loop when cadence, attention demand, or app-icon mode
            // changes. The first observation starts detection with no UI consumer.
            let advancedSettings = appState.settings.advanced
            iconRefreshIntervalObservationTask = Task { @MainActor [weak self] in
                var previous: (interval: TimeInterval, globalAttention: Bool, prefersAppIcon: Bool)?
                let changes = Observations {
                    (
                        interval: advancedSettings.iconRefreshInterval,
                        globalAttention: advancedSettings.surfaceItemsSeekingAttention,
                        prefersAppIcon: advancedSettings.alwaysUseAppIconForMenuBarItems
                    )
                }
                for await state in changes {
                    guard let self else { return }
                    guard previous?.interval != state.interval
                        || previous?.globalAttention != state.globalAttention
                        || previous?.prefersAppIcon != state.prefersAppIcon
                    else { continue }
                    previous = state
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
        let prefersAppIcon: Bool
    }

    /// Builds a NavigationStateSnapshot in a single MainActor hop.
    @MainActor
    private func makeNavigationStateSnapshot() -> NavigationStateSnapshot {
        guard let appState else {
            return NavigationStateSnapshot(
                isIceBarPresented: false,
                isSearchPresented: false,
                isAppFrontmost: false,
                isSettingsPresented: false,
                settingsNavigationIdentifier: nil,
                isItemHotkeyListExpanded: false,
                prefersAppIcon: false
            )
        }
        return NavigationStateSnapshot(
            isIceBarPresented: appState.navigationState.isIceBarPresented,
            isSearchPresented: appState.navigationState.isSearchPresented,
            isAppFrontmost: appState.navigationState.isAppFrontmost,
            isSettingsPresented: appState.navigationState.isSettingsPresented,
            settingsNavigationIdentifier: appState.navigationState.settingsNavigationIdentifier,
            isItemHotkeyListExpanded: isItemHotkeyListExpanded,
            prefersAppIcon: appState.settings.advanced.alwaysUseAppIconForMenuBarItems
        )
    }

    /// A background capture runs only for a visible consumer, or when requested
    /// while the layout pane is open (#759).
    static nonisolated func shouldAllowBackgroundCapture(
        hasVisibleConsumer: Bool,
        allowBackgroundCapture: Bool,
        isSettingsPaneOpen: Bool
    ) -> Bool {
        hasVisibleConsumer || (allowBackgroundCapture && isSettingsPaneOpen)
    }

    /// Returns the identifiers a section needs in the next live capture.
    ///
    /// Visible consumers and global attention take the whole section; trigger-only
    /// demand is intersected with it so unrelated icons stay out of the batch.
    static nonisolated func requiredCaptureIdentifiers(
        availableIdentifiers: some Sequence<String>,
        consumerNeedsWholeSection: Bool,
        globalAttentionNeedsWholeSection: Bool,
        attentionTriggerIdentifiers: Set<String>
    ) -> Set<String> {
        let available = Set(availableIdentifiers)
        if consumerNeedsWholeSection || globalAttentionNeedsWholeSection {
            return available
        }
        return available.intersection(attentionTriggerIdentifiers)
    }

    /// Refreshes the cache for currently visible consumers, or keeps a warm
    /// background snapshot ready for the layout settings pane when no consumer
    /// is visible.
    private func refreshVisibleConsumersOrPrewarmLayoutCache(allowBackgroundCapture: Bool = false) async {
        guard appState != nil else {
            return
        }

        let nav = await MainActor.run {
            makeNavigationStateSnapshot()
        }

        let hasVisibleConsumer = hasVisibleCaptureConsumer(nav: nav)

        // Background capture is gated by isSettingsPaneOpen (#759).
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

    private func hasVisibleCaptureConsumer(nav: NavigationStateSnapshot) -> Bool {
        // App-icon mode renders no capture, so no visible consumer needs one.
        if nav.prefersAppIcon {
            return false
        }
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
            // Read from the snapshot so it stays race-free off the main actor.
            return nav.isItemHotkeyListExpanded
        default:
            return false
        }
    }

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
            isItemHotkeyListExpanded: isItemHotkeyListExpanded,
            prefersAppIcon: appState.settings.advanced.alwaysUseAppIconForMenuBarItems
        )
        return hasVisibleCaptureConsumer(nav: nav)
    }

    @MainActor
    private func startLiveRefreshIfNeeded() {
        guard appState != nil else {
            liveRefreshTask?.cancel()
            liveRefreshTask = nil
            return
        }

        // Called from synchronous sink closures, hence the Task.
        Task { [weak self] in
            guard let self else { return }
            let nav = await MainActor.run {
                self.makeNavigationStateSnapshot()
            }
            let globalAttentionDetection = self.appState?.settings.advanced.surfaceItemsSeekingAttention == true
            let needsRefresh = self.hasVisibleCaptureConsumer(nav: nav)
                || !self.attentionDetectionItemIdentifiers.isEmpty
                || globalAttentionDetection

            if needsRefresh {
                guard self.liveRefreshTask == nil else { return }
                MenuBarItemImageCache.diagLog.debug(
                    "Starting live refresh (iceBar=\(nav.isIceBarPresented), search=\(nav.isSearchPresented), settings=\(nav.isSettingsPresented), attentionTriggers=\(self.attentionDetectionItemIdentifiers.count), globalAttention=\(globalAttentionDetection))"
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
    /// One loop serves every consumer view. refreshImages is @concurrent; only
    /// navigation reads run on the main actor. Uses the weak appState to avoid a retain cycle.
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

            let preferredDisplayID = preferredCaptureDisplayID(appState: appState)
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

            // Sections a UI consumer needs in full. Trigger demand is per identifier
            // below, so one watched icon can't pull in a whole section.
            var consumerSections = Set<MenuBarSection.Name>()
            let isLayoutPane = nav.isSettingsPresented
                && nav.settingsNavigationIdentifier == .menuBarLayout
            let isHotkeyListVisible = nav.isSettingsPresented
                && nav.settingsNavigationIdentifier == .hotkeys
                && isItemHotkeyListExpanded
            if nav.isSearchPresented || isLayoutPane || isHotkeyListVisible {
                if nav.isSearchPresented, !isLayoutPane, !isHotkeyListVisible {
                    // Search is the only consumer here that can omit sections.
                    let advanced = appState.settings.advanced
                    consumerSections = Set(MenuBarSection.Name.allCases.filter { name in
                        switch name {
                        case .visible: advanced.searchIncludeVisible
                        case .hidden: advanced.searchIncludeHidden
                        case .alwaysHidden: advanced.searchIncludeAlwaysHidden
                        }
                    })
                } else {
                    consumerSections = Set(MenuBarSection.Name.allCases)
                }
            } else if nav.isIceBarPresented,
                      let current = appState.menuBarManager.iceBarPanel.currentSection
            {
                consumerSections = [current]
            }

            let globalAttentionDetection = appState.settings.advanced.surfaceItemsSeekingAttention
            let triggerAttentionIdentifiers = attentionDetectionItemIdentifiers
            guard !consumerSections.isEmpty
                || globalAttentionDetection
                || !triggerAttentionIdentifiers.isEmpty
            else {
                try? await Task.sleep(for: .milliseconds(50))
                continue
            }

            // Every section, so trigger demand follows a watched item that moves.
            let sections = MenuBarSection.Name.allCases

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
            var capturedTags = [MenuBarItemTag]()

            for section in sections {
                let availableItems = appState.itemManager.itemCache.managedItems(for: section)
                let requiredIdentifiers = Self.requiredCaptureIdentifiers(
                    availableIdentifiers: availableItems.map(\.tag.tagIdentifier),
                    consumerNeedsWholeSection: consumerSections.contains(section),
                    globalAttentionNeedsWholeSection: globalAttentionDetection && section != .visible,
                    attentionTriggerIdentifiers: triggerAttentionIdentifiers
                )
                let items = availableItems.filter {
                    requiredIdentifiers.contains($0.tag.tagIdentifier)
                }
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
                        capturedTags.append(contentsOf: items.map(\.tag))
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
                capturedTags.append(contentsOf: hiddenItems.map(\.tag))
            case .alwaysHidden:
                lastAlwaysHiddenRefreshAt = now
                MenuBarItemImageCache.diagLog.debug(
                    "liveRefresh (capture): alwaysHidden items=\(alwaysHiddenItems.count)"
                )
                await withCapturePermit {
                    await refreshImages(of: alwaysHiddenItems, scale: scale)
                }
                capturedTags.append(contentsOf: alwaysHiddenItems.map(\.tag))
            case .visible, nil:
                break
            }

            await MainActor.run {
                storeImages(for: screen.displayID, capturedTags: capturedTags)
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

    /// Captures a composite image of the given items and crops out each one.
    ///
    /// Takes pre-fetched bounds to avoid a TOCTOU race between lookup and capture.
    /// Items must be on-screen; the caller filters the rest.
    private nonisolated func compositeCapture(
        _ itemsWithBounds: [(item: MenuBarItem, bounds: CGRect)],
        scale: CGFloat
    ) async -> CaptureResult {
        var result = CaptureResult()

        var windowIDs = [CGWindowID]()
        var storage = [CGWindowID: (MenuBarItem, CGRect)]()
        var boundsUnion = CGRect.null

        for (item, bounds) in itemsWithBounds {
            // A degenerate window corrupts the slice geometry and the union width
            // that resolvedScale reads (#990).
            guard Self.isCapturableBounds(bounds) else {
                MenuBarItemImageCache.diagLog.debug(
                    "compositeCapture: skipping degenerate bounds for \(item.logString) (\(bounds.width)x\(bounds.height))"
                )
                result.excluded.append(item)
                continue
            }
            windowIDs.append(item.windowID)
            storage[item.windowID] = (item, bounds)
            boundsUnion = boundsUnion.union(bounds)
        }

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

        // SCK picks the scale of whichever display owns the filter, which on
        // mixed-scale setups may not be the one passed in (#990). Read it from the capture.
        guard let effectiveScale = MenuBarItemImageCache.resolvedScale(
            imagePixelWidth: compositeImage.width,
            boundsWidth: boundsUnion.width,
            expected: scale
        ) else {
            MenuBarItemImageCache.diagLog.warning(
                "compositeCapture: implausible scale — \(compositeImage.width)px wide for a \(boundsUnion.width)pt union at expected scale \(scale), excluding \(windowIDs.count) windows"
            )
            result.excluded = itemsWithBounds.map(\.item)
            return result
        }
        if effectiveScale != scale {
            MenuBarItemImageCache.diagLog.warning(
                "compositeCapture: capture scale \(effectiveScale) differs from display scale \(scale); using the captured scale"
            )
        }

        guard !compositeImage.isTransparent() else {
            MenuBarItemImageCache.diagLog.warning("compositeCapture: composite image is fully transparent (\(compositeImage.width)x\(compositeImage.height)) — screen recording permission may not be effective")
            result.excluded = itemsWithBounds.map(\.item)
            return result
        }

        MenuBarItemImageCache.diagLog.debug(
            "compositeCapture: composite image OK (\(compositeImage.width)x\(compositeImage.height)), cropping \(windowIDs.count) items"
        )

        var cropSuccessCount = 0
        var cropNilCount = 0
        var cropTransparentCount = 0
        for windowID in windowIDs {
            guard let (item, bounds) = storage[windowID] else {
                continue
            }

            if shouldSkipCapture(for: item) {
                MenuBarItemImageCache.diagLog.debug(
                    "Skipping composite capture for repeatedly failing item: \(item.logString)"
                )
                result.excluded.append(item)
                continue
            }

            let cropRect = CGRect(
                x: (bounds.origin.x - boundsUnion.origin.x) * effectiveScale,
                y: (bounds.origin.y - boundsUnion.origin.y) * effectiveScale,
                width: bounds.width * effectiveScale,
                height: bounds.height * effectiveScale
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

            cropSuccessCount += 1
            recordCaptureSuccess(for: item)
            result.images[item.tag] = CapturedImage(
                cgImage: croppedImage,
                scale: effectiveScale
            )
        }

        MenuBarItemImageCache.diagLog.debug(
            "compositeCapture: crops done — \(cropSuccessCount) ok, \(cropNilCount) nil, \(cropTransparentCount) transparent"
        )

        return result
    }

    /// The scale a captured image was actually taken at, or nil when the
    /// image cannot be trusted at any scale.
    ///
    /// Pixel width over point width is the real capture scale; when it
    /// disagrees with `expected`, it wins, since SCK may have chosen another display.
    ///
    /// A derived scale off every real backing scale means stale bounds, so drop
    /// the item: a missing icon recovers, a wrongly-scaled one gets cached.
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

        // Integer pixel widths make narrow items noisy.
        if abs(derived - expected) <= scaleTolerance {
            return expected
        }

        // Anything off a real backing scale is bad input, not a mismatch.
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

            // SCK captures at the scale of the display it picks by frame intersection.
            // On mixed-scale setups a wrong scale doubles the icon's size (#851).
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
        // Our control items always capture transparent; skip them to avoid an
        // endless fail/blacklist/retry cycle.
        let capturable = items.filter { !$0.isControlItem }

        // Composite capture doesn't handle the overlaps a move can leave.
        if await appState.itemManager.lastMoveOperationOccurred(
            within: .seconds(2)
        ) {
            MenuBarItemImageCache.diagLog.debug("Capturing individually due to recent item movement")
            return await individualCapture(capturable, scale: scale)
        }

        // Off-screen items inflate boundsUnion and fail the whole composite on
        // width. refreshImages captures them instead.
        // isWindowOnScreen() can't be used: macOS reports hidden items as on-screen.
        let displayID = Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
        let screenFrame = await MainActor.run {
            NSScreen.screens.first { $0.displayID == displayID }?.frame
        }

        // One bounds fetch for both the filter and compositeCapture avoids a TOCTOU race.
        var onScreenItemsWithBounds: [(item: MenuBarItem, bounds: CGRect)] = []
        var offScreenCount = 0
        var nilBoundsCount = 0

        for item in capturable {
            guard let bounds = Bridging.getWindowBounds(for: item.windowID) else {
                // No capture path works without bounds.
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

        // Keep excluded items so they can be logged elsewhere.
        individualResult.images.merge(compositeResult.images) { _, new in new }

        return individualResult
    }

    /// Lightweight image refresh for the IceBar.
    ///
    /// One composite capture, cropped per item. Updates LRU order but skips
    /// eviction, failure tracking, and cleanup, and skips unchanged images.
    ///
    /// @concurrent because nonisolated alone stays on the caller's actor
    /// (SE-0461), which would put the capture work on the main thread.
    @concurrent
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
            // A degenerate window parked off-screen stretches boundsUnion across
            // the gap, and the width check then discards every batch.
            guard Self.isCapturableBounds(bounds) else {
                MenuBarItemImageCache.diagLog.debug(
                    "refreshImages: skipping degenerate bounds for \(item.logString) (\(bounds.width)x\(bounds.height))"
                )
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

        // SCK is leak-free but display-bounded, so only for on-screen items.
        let compositeImage = await ScreenCapture.captureWindowsAsync(
            with: windowIDs,
            option: captureOption
        )
        guard let compositeImage else {
            MenuBarItemImageCache.diagLog.debug("refreshImages: capture failed, skipping")
            return
        }

        // A 2x capture of a 1x display is a good image, not a mismatch (#990).
        guard let effectiveScale = MenuBarItemImageCache.resolvedScale(
            imagePixelWidth: compositeImage.width,
            boundsWidth: boundsUnion.width,
            expected: scale
        ) else {
            MenuBarItemImageCache.diagLog.debug(
                "refreshImages: implausible scale (\(compositeImage.width)px for a \(boundsUnion.width)pt union at expected scale \(scale)), skipping"
            )
            return
        }
        if effectiveScale != scale {
            MenuBarItemImageCache.diagLog.debug(
                "refreshImages: capture scale \(effectiveScale) differs from display scale \(scale); using the captured scale"
            )
        }

        guard !compositeImage.isTransparent() else {
            MenuBarItemImageCache.diagLog.debug("refreshImages: composite is transparent, skipping")
            return
        }

        var newImages = [MenuBarItemTag: CapturedImage]()
        for windowID in windowIDs {
            guard let (item, bounds) = storage[windowID] else { continue }
            let cropRect = CGRect(
                x: (bounds.origin.x - boundsUnion.origin.x) * effectiveScale,
                y: (bounds.origin.y - boundsUnion.origin.y) * effectiveScale,
                width: bounds.width * effectiveScale,
                height: bounds.height * effectiveScale
            )
            // No per-item transparency check: transparent crops are spacers.
            guard let image = compositeImage.cropping(to: cropRect)?.detachedCopy() else {
                continue
            }
            newImages[item.tag] = CapturedImage(cgImage: image, scale: effectiveScale)
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

    /// Captures a fresh batch for image-comparison triggers via the helper process.
    func captureCurrentImages(
        forItemIdentifiers identifiers: Set<String>
    ) async -> [String: CGImage] {
        guard let appState, !identifiers.isEmpty else { return [:] }

        let requests: [IdentifierCaptureRequest] = appState.itemManager.itemCache.managedItems.compactMap { item in
            let identifier = item.tag.tagIdentifier
            guard identifiers.contains(identifier) else { return nil }
            return IdentifierCaptureRequest(identifier: identifier, windowID: item.windowID)
        }
        guard !requests.isEmpty else { return [:] }

        let preferredDisplayID = appState.itemManager.itemCache.displayID
        guard let screen = Self.resolveScreen(preferredDisplayID: preferredDisplayID) else {
            return [:]
        }

        do {
            try await captureSemaphore.wait()
        } catch {
            return [:]
        }
        let captured = await Self.captureCurrentImages(
            requests: requests,
            scale: screen.screen.backingScaleFactor,
            option: captureOption
        )
        await captureSemaphore.signal()
        return captured
    }

    @concurrent
    private static nonisolated func captureCurrentImages(
        requests: [IdentifierCaptureRequest],
        scale: CGFloat,
        option: CGWindowImageOption
    ) async -> [String: CGImage] {
        let frames = await MenuBarCaptureService.Connection.shared.capture(
            windowIDs: requests.map(\.windowID),
            scale: scale,
            option: option
        )
        guard !frames.isEmpty, !Task.isCancelled else { return [:] }

        let identifierByWindowID = Dictionary(
            requests.map { ($0.windowID, $0.identifier) },
            uniquingKeysWith: { first, _ in first }
        )
        var images = [String: CGImage]()
        for frame in frames {
            guard let identifier = identifierByWindowID[frame.windowID],
                  let image = MenuBarCaptureService.makeImage(from: frame)
            else { continue }
            images[identifier] = image
        }
        return images
    }

    private func applyRefreshedImages(_ newImages: [MenuBarItemTag: CapturedImage]) {
        var updatedCount = 0
        for (tag, newImage) in newImages where !CapturedImage.isVisuallyEqual(images[tag], newImage) {
            images[tag] = newImage
            updateAccessOrder(for: tag)
            updatedCount += 1
        }
        // Record unchanged captures too: steady samples are what age a blink out.
        recordForAttention(newImages)
        if updatedCount > 0 {
            MenuBarItemImageCache.diagLog.debug(
                "refreshImages: ✓ updated \(updatedCount)/\(newImages.count) items (visually changed)"
            )
        }
    }

    /// Feeds a batch of captures to the attention detector and republishes
    /// the verdict when it changes.
    private func recordForAttention(_ newImages: [MenuBarItemTag: CapturedImage]) {
        let globalAttentionDetection = Defaults.bool(forKey: .surfaceItemsSeekingAttention)
        guard globalAttentionDetection || !attentionDetectionItemIdentifiers.isEmpty else {
            if !tagsSeekingAttention.isEmpty {
                tagsSeekingAttention = []
            }
            return
        }

        let detectionTags = globalAttentionDetection
            ? Set(images.keys)
            : Set(images.keys.filter {
                attentionDetectionItemIdentifiers.contains($0.tagIdentifier)
            })
        let now = Date.timeIntervalSinceReferenceDate
        for (tag, image) in newImages where detectionTags.contains(tag) {
            attentionDetector.record(fingerprint: image.fingerprint, for: tag, at: now)
        }
        attentionDetector.retain(detectionTags)

        let seeking = Set(detectionTags.filter { attentionDetector.isSeekingAttention($0, at: now) })
        guard seeking != tagsSeekingAttention else { return }
        tagsSeekingAttention = seeking
        if !seeking.isEmpty {
            MenuBarItemImageCache.diagLog.debug(
                "attention: \(seeking.count) item(s) seeking attention"
            )
        }
    }

    /// Clears an item's recorded history, so surfacing it does not
    /// immediately re-trigger on the blink that surfaced it.
    func clearAttention(for tag: MenuBarItemTag) {
        attentionDetector.reset(tag)
        tagsSeekingAttention.remove(tag)
    }

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

    private func handleMemoryPressure() {
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

    // MARK: Cache Access

    private func updateAccessOrder(for tag: MenuBarItemTag) {
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
    private static func image(
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
    private func validateAndCleanupInvalidEntries(
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

    // MARK: Update Cache

    /// Display to capture from while a consumer is visible.
    ///
    /// Prefer the Thaw Bar's screen when it is presented so a cross-display
    /// open does not keep sampling the previous menu bar's icon tint.
    @MainActor
    private func preferredCaptureDisplayID(
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

    @MainActor
    func clearAll() {
        images.removeAll()
        accessOrder.removeAll()
        imagesByDisplay.removeAll()
        lastCaptureDisplayID = nil
        failedCapturesLock.withLock { $0.removeAll() }
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
