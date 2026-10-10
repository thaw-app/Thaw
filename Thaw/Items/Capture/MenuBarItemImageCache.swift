//
//  MenuBarItemImageCache.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import MenuBarModel
import Observation
import os.lock
import PlatformRuntimeKit
import ThawCapture

/// One item's published capture, observable on its own.
///
/// Observing capturesByTag would wake every tile on any item's capture (a
/// clock repaints each second), so tiles watch a slot and only the cache
/// watches the dictionary.
@Observable
@MainActor
final class MenuBarItemGlyphSlot {
    private(set) var capture: MenuBarItemGlyphCapture?

    fileprivate init(capture: MenuBarItemGlyphCapture?) {
        self.capture = capture
    }

    /// File-private so only the cache can publish into a slot.
    fileprivate func publish(_ capture: MenuBarItemGlyphCapture?) {
        self.capture = capture
    }
}

/// Holds one screenshot crop per menu bar item and keeps it current for
/// whichever Thaw surface is on screen.
///
/// Unchecked Sendable rather than @MainActor so capture can run off the main
/// actor. Stored properties are touched only on the main actor; the
/// nonisolated capture path uses locals, immutable lets and the two locks.
@Observable
final class MenuBarItemImageCache: @unchecked Sendable {
    static nonisolated let diagLog = DiagLog(category: "MenuBarItemImageCache")
    /// Seam over WindowServer reads; tests substitute a fake.
    let windowServer: any WindowServerReading
    nonisolated let screenIsLocked: @Sendable () -> Bool
    /// Whether a capture asked for now would run; false while no Thaw surface is open.
    nonisolated let captureIsAllowed: @Sendable () -> Bool

    init(
        windowServer: any WindowServerReading = LiveWindowServerReader(),
        screenIsLocked: @escaping @Sendable () -> Bool = { ScreenLock.isLocked },
        captureIsAllowed: @escaping @Sendable () -> Bool = { ScreenCapture.acceptsCaptures }
    ) {
        self.windowServer = windowServer
        self.screenIsLocked = screenIsLocked
        self.captureIsAllowed = captureIsAllowed
    }

    /// Consecutive capture passes skipped because the bar was mid-reflow.
    var consecutiveReflowSkips = 0

    /// The lock state the last capture pass saw. See
    /// skipCaptureWhileScreenLocked(_:).
    @ObservationIgnored var screenLockTransitions = ScreenLockTransitions()

    /// Whether a concealed-section prewarm is running, and the prewarms
    /// queued behind it. Main actor only. See
    /// prewarmConcealedImages(sections:onlyMissingImages:).
    @ObservationIgnored var isConcealedPrewarmRunning = false
    /// When recapture last asked for a fresh inventory walk; see requestInventoryRefresh(reason:).
    @ObservationIgnored var lastInventoryRefreshRequest: ContinuousClock.Instant?
    @ObservationIgnored var concealedPrewarmWaiters = [CheckedContinuation<Void, Never>]()

    /// Shares one recapture pass among overlapping requests. Main actor only.
    @ObservationIgnored let recaptureCoalescer = RecaptureCoalescer()

    /// How many passes a live reflow may suppress before one runs regardless.
    static nonisolated let maximumReflowSkips = 8

    /// The published cache itself: the most recent crop trusted for each item.
    ///
    /// A missing tag tells consumers to fall back to the app icon, so stale
    /// entries are removed rather than kept.
    private(set) var capturesByTag = [MenuBarItemTag: MenuBarItemGlyphCapture]()

    // Every write from the extension files funnels through these five, so
    // capturesByTag keeps its read-only facade outside this file.

    func setCapture(_ capture: MenuBarItemGlyphCapture, for tag: MenuBarItemTag) {
        capturesByTag[tag] = capture
    }

    @discardableResult
    func removeCapture(for tag: MenuBarItemTag) -> MenuBarItemGlyphCapture? {
        capturesByTag.removeValue(forKey: tag)
    }

    func removeAllCaptures() {
        capturesByTag.removeAll()
    }

    func keepCaptures(where shouldBeKept: (_ tag: MenuBarItemTag, _ capture: MenuBarItemGlyphCapture) throws -> Bool) rethrows {
        capturesByTag = try capturesByTag.filter { try shouldBeKept($0.key, $0.value) }
    }

    func replaceCaptures(with captures: [MenuBarItemTag: MenuBarItemGlyphCapture]) {
        capturesByTag = captures
    }

    /// Maximum number of images to cache to prevent memory growth
    static let maxCacheSize = 200

    /// Per-item record of how often each item's image actually changes,
    /// populated from the pixel comparison refreshImages already performs.
    /// Read it through volatility(for:).
    let volatilityIndex = MenuBarItemVolatilityIndex()

    /// LRU tracking: lower counter values are least recently used.
    ///
    /// Ignored by observation because every image(for:) read mutates it,
    /// which would otherwise loop view bodies forever.
    @ObservationIgnored
    var accessTimestamps: [MenuBarItemTag: UInt64] = [:]

    /// Monotonic counter incremented on each access, used for LRU ordering.
    @ObservationIgnored
    var accessCounter: UInt64 = 0

    /// Failed capture tracking to skip repeatedly failing items
    nonisolated struct FailedCapture: Hashable {
        let tag: MenuBarItemTag
        let failureCount: Int
        let lastFailureTime: Date
    }

    let failedCapturesLock = OSAllocatedUnfairLock<[MenuBarItemTag: FailedCapture]>(initialState: [:])

    /// Displays whose hosting-window capture already failed since it last
    /// succeeded, so the repeats log at debug instead of warning.
    let hostingFailureWarnedDisplays = OSAllocatedUnfairLock<Set<CGDirectDisplayID>>(initialState: [])

    /// Configuration for failed capture handling
    static nonisolated let maxFailuresBeforeBlacklist = 3
    static nonisolated let blacklistCooldownSeconds: TimeInterval = 30

    /// Minimum spacing between counted strikes, so one reflow blip that
    /// produces several blank captures cannot blacklist an item on its own.
    static nonisolated let minimumFailureSpacingSeconds: TimeInterval = 0.5

    /// The disk half: the cache file, its format, and the save queue. The
    /// cache owns the policy, this owns the file.
    let diskStore = MenuBarItemImageCacheDiskStore()

    /// Weak so the cache never keeps the app alive; every method that needs it
    /// bails out quietly when it has gone.
    weak var appState: AppState?

    /// Captured at activate(with:) so recapture paths can refuse to act on
    /// a bar disturbed by a recent move without reaching through
    /// appState.itemManager.
    var moveActivity: MoveOperationTracker?

    /// The settings this component reads. MenuBarEngineConfiguration states
    /// why the engine holds this rather than AppState.
    var configuration: any MenuBarEngineConfiguration = AppSettings.engineDefaults

    /// Subscriptions installed by installObservers(), released as a group.
    var cancellables = Set<AnyCancellable>()

    /// Watches AppNavigationState's @Observable properties.
    private var navigationStateObservationTask: Task<Void, Never>?

    /// Task observing AdvancedSettings.iconRefreshInterval, which is
    /// @Observable rather than a Combine ObservableObject.
    private var iconRefreshIntervalObservationTask: Task<Void, Never>?

    /// Task observing AdvancedSettings.alwaysUseAppIconForMenuBarItems.
    private var alwaysUseAppIconObservationTask: Task<Void, Never>?

    private var memoryPressureSource: DispatchSourceMemoryPressure?

    /// The currently running cache update task, if any.
    var currentUpdateTask: Task<Void, Never>?

    /// The currently running live-refresh task, if any.
    private var liveRefreshTask: Task<Void, Never>?

    /// Pending idle trim. Scheduled when the last capture consumer goes
    /// away, cancelled the moment one comes back.
    @ObservationIgnored
    var idleTrimTask: Task<Void, Never>?

    /// Whether loadFromDisk has been attempted. The disk load is deferred
    /// from activate(with:) to the first consumer open so decoded
    /// CGImage backing stores are not resident at bootstrap.
    @ObservationIgnored
    var hasLoadedFromDisk = false

    /// The disk load still decoding, if any, so a reset or an idle trim can
    /// abandon it instead of racing it.
    @ObservationIgnored
    var diskLoadTask: Task<Void, Never>?

    /// Bumped whenever the cache is emptied on purpose. A load merges only
    /// under the generation it started with, so it cannot restore released images.
    @ObservationIgnored
    var diskLoadGeneration = 0

    /// A slot the cache publishes into, kept only for as long as the consumer
    /// that asked for it holds on.
    struct WeakGlyphSlot {
        weak var slot: MenuBarItemGlyphSlot?
    }

    /// The per-item slots handed out by glyphSlot(for:).
    ///
    /// Ignored by observation so asking for a slot from a view body does not
    /// invalidate that body.
    @ObservationIgnored
    private var glyphSlotsByTag = [MenuBarItemTag: WeakGlyphSlot]()

    /// Whether the slot fan-out is already watching the cache. The tracking
    /// chain re-arms itself, so a second installObservers() would leave two
    /// of them running for the life of the process.
    @ObservationIgnored
    private var isObservingCapturesForGlyphSlots = false

    /// How long the app must go without a visible capture consumer before
    /// the cache is dropped.
    static let idleTrimDelay: Duration = .seconds(30)

    /// Whether the per-item hotkey list is expanded. While collapsed it shows
    /// no item icons, so the live capture loop can stay off.
    var isItemHotkeyListExpanded = false {
        didSet {
            guard oldValue != isItemHotkeyListExpanded else { return }
            startLiveRefreshIfNeeded()
        }
    }

    @MainActor
    deinit {
        memoryPressureSource?.cancel()
        currentUpdateTask?.cancel()
        liveRefreshTask?.cancel()
        idleTrimTask?.cancel()
        diskLoadTask?.cancel()
    }

    // MARK: Activation

    /// Binds the cache to the app, installs its observers, and restores the
    /// previous run's images.
    ///
    /// Called once, from AppState. Restored entries keep the first frame from
    /// being all app icons until live captures replace them.
    @MainActor
    func activate(with appState: AppState) {
        self.appState = appState
        configuration = appState.settings
        moveActivity = appState.itemManager.moveActivity
        installObservers()

        // Disk images load lazily on the first consumer open, not at bootstrap.

        let hasVisible = hasVisibleCaptureConsumer()
        guard hasVisible else {
            return
        }

        loadFromDiskIfNeeded()

        currentUpdateTask?.cancel()
        currentUpdateTask = Task { [weak self] in
            await self?.refreshVisibleConsumersOrPrewarmLayoutCache()
        }
    }

    /// Whether anything off screen still has a claim on fresh pixels.
    ///
    /// Only the alert-reveal watcher counts: it compares capture to capture.
    /// A layout pane opened earlier does not, or background passes would undo
    /// the idle trim.
    @MainActor
    private func hasBackgroundCaptureDemand() -> Bool {
        !MenuBarItemAlertReveals.identifiers().isEmpty
    }

    /// First consumer opened: cancel any pending trim, load disk once,
    /// and recapture now if something is watching.
    @MainActor
    func prepareForPresentation() {
        idleTrimTask?.cancel()
        idleTrimTask = nil
        loadFromDiskIfNeeded()
        Task { [weak self] in
            guard let self, self.appState?.navigationState.hasCaptureUI == true else { return }
            await self.recaptureNow(sections: MenuBarSection.Name.allCases)
        }
    }

    /// Installs every subscription the cache runs on, replacing any earlier set.
    ///
    /// Space switches, display changes and item-cache digests feed one
    /// debounced recapture; navigation state starts and stops the live loop.
    @MainActor
    private func installObservers() {
        var installed = Set<AnyCancellable>()

        // The one watcher of the whole dictionary. Everything drawing a single
        // item follows its own slot instead; see glyphSlot(for:).
        if !isObservingCapturesForGlyphSlots {
            isObservingCapturesForGlyphSlots = true
            observeCapturesForGlyphSlots()
        }

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

            // Bridges the observed item cache into the Combine merge below.
            let itemCacheChangeSubject = PassthroughSubject<Void, Never>()
            let itemCacheTask = Task { @MainActor [weak self, itemManager = appState.itemManager] in
                let changes = Observations { Self.captureInvalidationKey(itemManager.itemCache) }
                var previous: CaptureInvalidationKey?
                var isFirst = true
                for await key in changes {
                    guard self != nil else { return }
                    defer { isFirst = false }
                    guard key != previous else { continue }
                    previous = key
                    if !isFirst {
                        itemCacheChangeSubject.send(())
                    }
                }
            }
            AnyCancellable { itemCacheTask.cancel() }
                .store(in: &installed)
            let itemCacheChangePublisher: AnyPublisher<Void, Never> = itemCacheChangeSubject
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
                // Capture only if something will read the result; a closed
                // layout pane refills its own cache when it opens.
                let nav = self.makeNavigationStateSnapshot()
                let hasVisible = self.hasVisibleCaptureConsumer(nav: nav)
                let hasBackgroundDemand = self.hasBackgroundCaptureDemand()
                guard hasVisible || hasBackgroundDemand else {
                    return
                }
                self.currentUpdateTask?.cancel()
                self.currentUpdateTask = Task { [weak self, hasBackgroundDemand] in
                    await self?.refreshVisibleConsumersOrPrewarmLayoutCache(
                        allowBackgroundCapture: hasBackgroundDemand
                    )
                }
            }
            .store(in: &installed)

            // No debounce needed: startLiveRefreshIfNeeded() is idempotent.
            navigationStateObservationTask?.cancel()
            navigationStateObservationTask = Task { @MainActor [weak self] in
                let changes = Observations { [weak self] in
                    self?.makeNavigationStateSnapshot().liveCaptureScope
                }
                for await _ in changes {
                    guard let self else { return }
                    self.startLiveRefreshIfNeeded()
                }
            }

            // Hotkey list expansion is handled by isItemHotkeyListExpanded's didSet.

            // Restart the live loop on interval changes. The initial emission
            // is a no-op through the liveRefreshTask guard.
            iconRefreshIntervalObservationTask?.cancel()
            iconRefreshIntervalObservationTask = Task { @MainActor [weak self, advancedSettings = appState.settings.advanced] in
                let changes = Observations { advancedSettings.iconRefreshInterval }
                for await _ in changes {
                    guard let self else { return }
                    guard self.liveRefreshTask != nil else { continue }
                    self.liveRefreshTask?.cancel()
                    self.liveRefreshTask = nil
                    self.startLiveRefreshIfNeeded()
                }
            }

            // Entries rot unread while app icons are on, so rebuild the cache
            // when the preference turns off. The initial value is skipped.
            alwaysUseAppIconObservationTask?.cancel()
            alwaysUseAppIconObservationTask = Task { @MainActor [weak self, advancedSettings = appState.settings.advanced] in
                var previous: Bool?
                let changes = Observations { advancedSettings.alwaysUseAppIconForMenuBarItems }
                for await alwaysUseAppIcon in changes {
                    guard let self else { return }
                    defer { previous = alwaysUseAppIcon }
                    guard let previous, previous != alwaysUseAppIcon, !alwaysUseAppIcon else { continue }
                    self.handleLivePreviewsReenabled()
                }
            }
        }

        cancellables = installed
    }

    // MARK: Live Refresh

    @MainActor
    func makeNavigationStateSnapshot() -> NavigationStateSnapshot {
        guard let appState else {
            return NavigationStateSnapshot(
                isThawBarPresented: false,
                isSearchPresented: false,
                isAppFrontmost: false,
                isSettingsPresented: false,
                settingsNavigationIdentifier: nil,
                isItemHotkeyListExpanded: false,
                isSimpleModeSettings: false
            )
        }
        return NavigationStateSnapshot(
            isThawBarPresented: appState.navigationState.isThawBarPresented,
            isSearchPresented: appState.navigationState.isSearchPresented,
            isAppFrontmost: appState.navigationState.isAppFrontmost,
            isSettingsPresented: appState.navigationState.isSettingsPresented,
            settingsNavigationIdentifier: appState.navigationState.settingsNavigationIdentifier,
            isItemHotkeyListExpanded: isItemHotkeyListExpanded,
            isSimpleModeSettings: appState.navigationState.isSimpleModeSettings
        )
    }

    /// Refreshes the cache for whatever currently needs it, on screen or not.
    ///
    /// The background arm (alert reveal only) re-arms the idle trim on the way
    /// out, or it would leave a cache nobody is looking at resident.
    private func refreshVisibleConsumersOrPrewarmLayoutCache(allowBackgroundCapture: Bool = false) async {
        guard appState != nil else {
            return
        }

        let nav = await MainActor.run { makeNavigationStateSnapshot() }

        let hasVisibleConsumer = hasVisibleCaptureConsumer(nav: nav)

        guard hasVisibleConsumer || allowBackgroundCapture else {
            return
        }

        if hasVisibleConsumer {
            await recaptureIfWarranted(nav: nav)
        } else {
            await recaptureIfWarranted(
                sections: MenuBarSection.Name.allCases,
                allowBackgroundCapture: true,
                nav: nav
            )
            await MainActor.run {
                guard !hasVisibleCaptureConsumer() else { return }
                scheduleIdleTrim()
            }
        }
    }

    /// Returns whether any visible surface currently needs live item captures.
    func hasVisibleCaptureConsumer(nav: NavigationStateSnapshot) -> Bool {
        nav.liveCaptureScope != .none
    }

    /// Convenience overload that reads current state on MainActor when no snapshot is provided.
    @MainActor
    func hasVisibleCaptureConsumer() -> Bool {
        hasVisibleCaptureConsumer(nav: makeNavigationStateSnapshot())
    }

    /// Starts or stops the live image refresh loop based on navigation state.
    @MainActor
    private func startLiveRefreshIfNeeded() {
        guard appState != nil else {
            liveRefreshTask?.cancel()
            liveRefreshTask = nil
            return
        }

        // Callers are synchronous sink closures.
        Task { [weak self] in
            guard let self else { return }
            let nav = await MainActor.run {
                self.makeNavigationStateSnapshot()
            }
            let needsRefresh = self.hasVisibleCaptureConsumer(nav: nav)

            if needsRefresh {
                self.idleTrimTask?.cancel()
                self.idleTrimTask = nil
                await MainActor.run { self.loadFromDiskIfNeeded() }
                guard self.liveRefreshTask == nil else { return }
                MenuBarItemImageCache.diagLog.debug(
                    "Starting live refresh (scope=\(nav.liveCaptureScope), simpleMode=\(nav.isSimpleModeSettings), thawBar=\(nav.isThawBarPresented), search=\(nav.isSearchPresented), settings=\(nav.isSettingsPresented))"
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
                self.scheduleIdleTrim()
            }
        }
    }

    /// One capture loop serving every consumer view. The capture pass runs off
    /// the main actor; appState is read weakly to avoid a retain cycle.
    @MainActor
    private func runLiveRefreshLoop() async {
        MenuBarItemImageCache.diagLog.debug("Live refresh loop started")

        // Hold the capture service open, or the helper exits after each
        // capture and every tick pays a process launch.
        let holdsCaptureService = ScreenCapture.routesThroughCaptureService
        if holdsCaptureService {
            await MenuBarCaptureServiceClient.shared.beginLiveConsumer()
        }
        defer {
            if holdsCaptureService {
                await MenuBarCaptureServiceClient.shared.endLiveConsumer()
            }
        }

        var changelessStreak = 0

        // Always Hidden refreshes at most once per second: those items are
        // captured off screen and rarely animate.
        var lastAlwaysHiddenRefresh: ContinuousClock.Instant?

        while !Task.isCancelled {
            guard let appState = self.appState else { break }
            let interval = configuration.iconRefreshInterval
            guard interval > 0 else {
                changelessStreak = 0
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            let ms = Self.backedOffTickMilliseconds(
                baseMilliseconds: Int(interval * 1000),
                changelessStreak: changelessStreak
            )
            try? await Task.sleep(for: .milliseconds(ms))
            guard !Task.isCancelled else { break }

            let nav = makeNavigationStateSnapshot()

            let displayID = appState.itemManager.itemDisplayID
                ?? windowServer.activeMenuBarDisplayID()
                ?? CGMainDisplayID()
            guard NSScreen.screens.contains(where: { $0.displayID == displayID }) else {
                changelessStreak = 0
                continue
            }

            let sections = nav.liveCaptureScope.sections(
                thawBarSection: appState.menuBarManager.thawBarPanel.currentSection
            )
            guard !sections.isEmpty else {
                // Keep looping rather than break: ThawBar close() nils
                // currentSection before isThawBarPresented, and the observer cancels us.
                changelessStreak = 0
                continue
            }

            // Hoisted: these are tick-global, not per-section.
            if moveActivity?.occurred(within: .seconds(2)) == true {
                changelessStreak = 0
                continue
            }
            if appState.itemManager.isResettingLayout {
                changelessStreak = 0
                continue
            }

            // Periodic rather than a bounded retry, since every bounded attempt
            // can land during a MenuBarAgent reflow and leave partial crops.
            var sectionsThisTick = sections
            if interval < 1, sectionsThisTick.contains(.alwaysHidden) {
                if let last = lastAlwaysHiddenRefresh, last.duration(to: .now) < .seconds(1) {
                    sectionsThisTick.removeAll { $0 == .alwaysHidden }
                } else {
                    lastAlwaysHiddenRefresh = .now
                }
            }
            guard !sectionsThisTick.isEmpty else {
                changelessStreak = 0
                continue
            }
            // A concealed section with no reveal in progress has nothing to
            // crop, so the pass is skipped and the poll drops to its floor.
            let capturable = MenuBarBackendProvider.current.capturableSections(
                from: sectionsThisTick,
                revealedSection: appState.menuBarManager.sectionController.revealedSection
            )
            guard !capturable.isEmpty else {
                changelessStreak = max(changelessStreak, Self.backoffFloorStreak)
                continue
            }
            if await recaptureNow(sections: sectionsThisTick) {
                changelessStreak = 0
            } else {
                changelessStreak += 1
            }
        }

        MenuBarItemImageCache.diagLog.debug("Live refresh loop stopped")
    }

    // MARK: Coverage

    /// Whether section has nothing renderable, so a caller should show an
    /// error or placeholder instead of a row of items.
    ///
    /// A total blackout test, not a completeness test: items drop in and out
    /// of the cache constantly. Missing screen recording permission returns true.
    @MainActor
    func hasNoRenderableItems(in section: MenuBarSection.Name) -> Bool {
        guard ScreenCapture.hasCachedScreenRecordingPermission else {
            MenuBarItemImageCache.diagLog.debug("hasNoRenderableItems(\(section.logString)): no screen recording permission (hasCachedScreenRecordingPermission=false)")
            return true
        }
        let items = appState?.itemManager.itemCache[section] ?? []
        guard !items.isEmpty else {
            // An empty section has nothing to fail at.
            return false
        }
        guard !items.contains(where: { capturesByTag[$0.tag] != nil }) else {
            return false
        }
        MenuBarItemImageCache.diagLog.debug("hasNoRenderableItems(\(section.logString)): no cached images found for \(items.count) items in section (total cached images: \(capturesByTag.count))")
        return true
    }
}

extension MenuBarItemImageCache {
    // MARK: Cache Access

    /// Updates the access order for a given tag to mark it as most recently used.
    func updateAccessOrder(for tag: MenuBarItemTag) {
        accessCounter += 1
        accessTimestamps[tag] = accessCounter
    }

    /// Gets an image from the cache and updates its access order.
    func image(for tag: MenuBarItemTag) -> MenuBarItemGlyphCapture? {
        guard let resolved = Self.cachedCapture(for: tag, in: capturesByTag) else {
            return nil
        }
        updateAccessOrder(for: resolved.tag)
        return resolved.capture
    }

    /// The slot a consumer should watch to follow one item's capture.
    ///
    /// Held weakly here and strongly by the caller, so a slot lives exactly as
    /// long as the view that asked for it. publishGlyphSlots() drops the
    /// empty entries on its next pass.
    @MainActor
    func glyphSlot(for tag: MenuBarItemTag) -> MenuBarItemGlyphSlot {
        if let existing = glyphSlotsByTag[tag]?.slot {
            return existing
        }
        let slot = MenuBarItemGlyphSlot(capture: image(for: tag))
        glyphSlotsByTag[tag] = WeakGlyphSlot(slot: slot)
        return slot
    }

    /// Moves the cache's current answer into every live slot.
    ///
    /// Resolves like image(for:), and bumps the access order so watched items
    /// stay out of the LRU's way.
    @MainActor
    private func publishGlyphSlots() {
        guard !glyphSlotsByTag.isEmpty else { return }

        var emptied = [MenuBarItemTag]()
        for (tag, box) in glyphSlotsByTag {
            guard let slot = box.slot else {
                emptied.append(tag)
                continue
            }
            let resolved = Self.cachedCapture(for: tag, in: capturesByTag)
            if let resolved {
                updateAccessOrder(for: resolved.tag)
            }
            guard !MenuBarItemGlyphCapture.isVisuallyEqual(slot.capture, resolved?.capture) else {
                continue
            }
            slot.publish(resolved?.capture)
        }
        for tag in emptied {
            glyphSlotsByTag.removeValue(forKey: tag)
        }
    }

    /// Re-arms the single observation that feeds every slot.
    ///
    /// Not an Observations task: the task would hold the cache that owns it, a
    /// cycle. onChange fires before the write lands, so the read is deferred.
    @MainActor
    private func observeCapturesForGlyphSlots() {
        withObservationTracking {
            _ = capturesByTag
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.publishGlyphSlots()
                self.observeCapturesForGlyphSlots()
            }
        }
    }

    /// Returns the current cache size for monitoring purposes.
    var cacheSize: Int {
        capturesByTag.count
    }

    /// Returns the number of tracked LRU entries for debugging.
    var lruEntryCount: Int {
        accessTimestamps.count
    }

    /// Validates cache entries and removes items with invalid window IDs.
    /// Tags in preserving are kept even if they are no longer in the item cache.
    /// Returns the number of items removed during cleanup.
    @MainActor
    func validateAndCleanupInvalidEntries(
        preserving preservedTags: Set<MenuBarItemTag> = []
    ) -> Int {
        guard let appState else { return 0 }

        var removedCount = 0
        let allValidTags = Set(
            appState.itemManager.managedItems.map(\.tag)
        )

        // Non-system items match ignoring window ID, so disk-loaded entries
        // (which have none) are not evicted.
        let invalidTags = capturesByTag.keys.filter { tag in
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
            capturesByTag.removeValue(forKey: invalidTag)
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

    /// Logs detailed cache information. Never called automatically.
    func logCacheStatus(_ context: String = "Manual check") {
        let imageSize = capturesByTag.count
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
}
