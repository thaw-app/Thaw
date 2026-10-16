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
    static nonisolated let diagLog = DiagLog(category: "MenuBarItemImageCache")

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
    static func resolveScreen(
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

    /// The cached item images, keyed by their corresponding tags.
    var images = [MenuBarItemTag: CapturedImage]()

    /// Display the current ``images`` were captured for. The light/dark tint is
    /// baked into the capture, so another display's cache shows wrong colors.
    var lastCaptureDisplayID: CGDirectDisplayID?

    /// Per-display icon snapshots so switching screens can restore the correct
    /// light/dark tint immediately instead of flashing the previous screen.
    @ObservationIgnored
    var imagesByDisplay = [CGDirectDisplayID: [MenuBarItemTag: CapturedImage]]()

    /// Tracks which items are blinking for attention.
    ///
    /// Not observable: it's fed on every capture. The verdict is published
    /// through tagsSeekingAttention instead.
    @ObservationIgnored var attentionDetector = MenuBarItemAttentionDetector()

    /// The items currently asking for attention.
    var tagsSeekingAttention: Set<MenuBarItemTag> = []

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
    @ObservationIgnored var trimmedImages = [MenuBarItemTag: (source: CGImage, image: NSImage)]()

    static let maxCacheSize = 200

    /// LRU tracking from least to most recently used.
    /// Cache reads update this from SwiftUI bodies, so it must not invalidate them.
    @ObservationIgnored var accessOrder = OrderedSet<MenuBarItemTag>()

    /// Serializes every WindowServer capture path, including explicit cache
    /// rebuilds and the live refresh loop.
    let captureSemaphore = SimpleSemaphore(value: 1)

    init(images: [MenuBarItemTag: CapturedImage] = [:]) {
        self.images = images
        accessOrder = OrderedSet(images.keys)
    }

    /// Failed capture tracking to skip repeatedly failing items
    struct FailedCapture: Hashable {
        let tag: MenuBarItemTag
        let failureCount: Int
        let lastFailureTime: Date
    }

    let failedCapturesLock = OSAllocatedUnfairLock<[MenuBarItemTag: FailedCapture]>(initialState: [:])

    /// Configuration for failed capture handling
    static nonisolated let maxFailuresBeforeBlacklist = 3
    static nonisolated let blacklistCooldownSeconds: TimeInterval = 30 // 30 seconds

    private let queue = DispatchQueue(
        label: "MenuBarItemImageCache",
        qos: .background
    )

    let captureOption: CGWindowImageOption = [
        .boundsIgnoreFraming, .bestResolution,
    ]

    weak var appState: AppState?

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
    var liveRefreshTask: Task<Void, Never>?

    /// Timestamp of the last Hidden-section capture.
    var lastHiddenRefreshAt: ContinuousClock.Instant?

    /// Timestamp of the last Always Hidden-section capture.
    var lastAlwaysHiddenRefreshAt: ContinuousClock.Instant?

    /// Whether a window's bounds can contribute to a composite capture.
    ///
    /// The capture APIs omit degenerate windows, so one would corrupt the slice geometry.
    static nonisolated func isCapturableBounds(_ bounds: CGRect) -> Bool {
        bounds.width > 0 && bounds.height > 0
    }

    /// Timestamp of the last visible-section SCK capture, used to rate-limit
    /// the on-screen path the same way the offscreen one already is.
    var lastSCKRefreshAt: ContinuousClock.Instant?

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
}
