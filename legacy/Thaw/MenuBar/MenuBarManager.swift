//
//  MenuBarManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AsyncAlgorithms
import Combine
import Observation
import SwiftUI

/// Manager for the state of the menu bar.
@MainActor
@Observable
final class MenuBarManager {
    /// Information for the menu bar's average color on the active screen.
    private(set) var averageColorInfo: MenuBarAverageColorInfo?

    /// Per-screen average colors for multi-monitor adaptive backgrounds.
    private(set) var averageColors: [CGDirectDisplayID: MenuBarAverageColorInfo] = [:]

    /// Per-screen wallpaper palettes, used by the adaptive gradient tint.
    ///
    /// Separate from ``averageColors``: a palette samples the whole wallpaper,
    /// or a small subject never survives bucketing.
    private(set) var wallpaperPalettes: [CGDirectDisplayID: WallpaperPalette] = [:]

    /// A Boolean value that indicates whether the menu bar is either always hidden
    /// by the system, or automatically hidden and shown by the system based on the
    /// location of the mouse.
    private(set) var isMenuBarHiddenBySystem = false

    /// A Boolean value that indicates whether the menu bar is hidden by the system
    /// according to a value stored in UserDefaults.
    private(set) var isMenuBarHiddenBySystemUserDefaults = false

    /// A Boolean value that indicates whether the "ShowOnHover" feature is allowed.
    var showOnHoverAllowed = true

    /// Timestamp of the last time a section was shown.
    private(set) var lastShowTimestamp: ContinuousClock.Instant?

    /// Reference to the settings window.
    private var settingsWindow: NSWindow?

    @ObservationIgnored
    private let diagLog = DiagLog(category: "MenuBarManager")

    @ObservationIgnored
    private weak var appState: AppState?

    /// Storage for internal observers.
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    /// Task observing `DisplaySettingsManager.configurations`, which is
    /// `@Observable` rather than a Combine `ObservableObject`.
    private var displayConfigurationsObservationTask: Task<Void, Never>?

    /// Task observing `settingsWindow`, re-subscribing the window's
    /// `isVisible` KVO publisher for each new non-nil window.
    private var settingsWindowObservationTask: Task<Void, Never>?

    /// Task observing `appearanceManager.configuration` for adaptive-color
    /// refresh start/stop.
    private var appearanceConfigurationObservationTask: Task<Void, Never>?

    /// Task observing `itemManager.itemCache`, debounced with AsyncAlgorithms.
    private var itemCacheHotkeyObservationTask: Task<Void, Never>?

    /// Task observing ``GeneralSettings/hideDockIconWhenToggling`` so an
    /// automatic hide already in flight can be reconciled when the setting
    /// turns on.
    private var hideDockIconWhenTogglingObservationTask: Task<Void, Never>?

    @MainActor
    deinit {
        displayConfigurationsObservationTask?.cancel()
        settingsWindowObservationTask?.cancel()
        settingsWindowVisibilityCancellable?.cancel()
        appearanceConfigurationObservationTask?.cancel()
        itemCacheHotkeyObservationTask?.cancel()
        hideDockIconWhenTogglingObservationTask?.cancel()
        attentionObservationTask?.cancel()
    }

    /// Per-item hotkeys, keyed by MenuBarItem.uniqueIdentifier. Each opens the
    /// item's menu when its key combination fires. Mirrors the per-profile
    /// hotkeys on ProfileManager.
    private(set) var itemHotkeys: [String: Hotkey] = [:]

    /// Reverse map from a hotkey instance to the item identifier it opens.
    /// Read by Hotkey.Listener when an openMenuBarItem hotkey fires.
    var hotkeyItemMap: [ObjectIdentifier: String] = [:]

    /// Cancellable for the periodic average-color refresh, active only while settings is visible.
    private var averageColorRefreshCancellable: AnyCancellable?

    /// Cancellable for `settingsWindow`'s `isVisible` KVO stream, resubscribed
    /// on each new non-nil `settingsWindow` value by `settingsWindowObservationTask`.
    @ObservationIgnored
    private var settingsWindowVisibilityCancellable: AnyCancellable?

    /// Cancellable for the periodic average-color refresh when adaptive background is active.
    private var adaptiveColorRefreshCancellable: AnyCancellable?

    /// True between screensDidSleep and screensDidWake. Captures skip while
    /// it's set; the wake handler recaptures anyway.
    @ObservationIgnored
    private var areDisplaysAsleep = false

    /// Task observing `imageCache.tagsSeekingAttention` for items that have
    /// started blinking while hidden.
    private var attentionObservationTask: Task<Void, Never>?

    /// Watches the system wallpaper index so an adaptive bar re-samples the
    /// moment the wallpaper changes instead of waiting out the poll above.
    private let wallpaperChangeMonitor = WallpaperChangeMonitor()

    /// Per-screen colors cached before sleep, restored on wake to avoid stale/white flash.
    private var sleepColorCache: [CGDirectDisplayID: MenuBarAverageColorInfo]?

    /// Identifies the most recently started capture pass, so results that land
    /// after a newer pass has published its own can be dropped.
    @ObservationIgnored
    private var captureGeneration = 0

    /// Polling state for adaptive wake stabilization.
    private var wakePollTimer: AnyCancellable?
    private var wakePollPrevColors: [CGDirectDisplayID: MenuBarAverageColorInfo]?
    private var wakePollStableCount = 0
    private var wakePollDidChange = false
    private var wakePollStartTime: Date?

    /// A Boolean value that indicates whether the application menus are hidden.
    private var isHidingApplicationMenus = false

    /// A Boolean value that indicates whether the application menus were hidden
    /// by a manual toggle (URL/hotkey), rather than automatically by section state.
    private var isManuallyHidingApplicationMenus = false

    /// The delayed force-activation started by ``hideApplicationMenus(manual:)``.
    /// Cancelled when explicit UI requests `.regular`, so the retry cannot
    /// reapply `.accessory` and hide a settings window's Dock icon.
    private var hideApplicationMenusActivationTask: Task<Void, Never>?

    /// Whether that pending retry would apply `.accessory`. `.regular`
    /// activations from the hide path itself must keep the 25 ms retry.
    private var pendingHideActivationIsAccessory = false

    /// The panel that contains the Thaw Bar interface.
    let iceBarPanel = IceBarPanel()

    /// The panel that contains the menu bar search interface.
    let searchPanel = MenuBarSearchPanel()

    /// The popover that contains a portable version of the menu bar
    /// appearance editor interface
    let appearanceEditorPanel = MenuBarAppearanceEditorPanel()

    /// The popover that contains a portable version of the menu bar
    /// layout editor interface
    let layoutEditorPanel = MenuBarLayoutEditorPanel()

    /// The managed sections in the menu bar.
    let sections = [
        MenuBarSection(name: .visible),
        MenuBarSection(name: .hidden),
        MenuBarSection(name: .alwaysHidden),
    ]

    /// A Boolean value that indicates whether at least one of the manager's
    /// sections is visible.
    var hasVisibleSection: Bool {
        sections.contains { !$0.isHidden }
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()
        iceBarPanel.performSetup(with: appState)
        searchPanel.performSetup(with: appState)
        appearanceEditorPanel.performSetup(with: appState)
        layoutEditorPanel.performSetup(with: appState)
        for section in sections {
            section.performSetup(with: appState)
        }
        rebuildItemHotkeys()
    }

    private func configureCancellables() {
        averageColorRefreshCancellable?.cancel()
        averageColorRefreshCancellable = nil
        hideDockIconWhenTogglingObservationTask?.cancel()
        hideDockIconWhenTogglingObservationTask = nil
        var c = Set<AnyCancellable>()

        NSApp.publisher(for: \.currentSystemPresentationOptions)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] options in
                guard let self else {
                    return
                }
                let hidden = options.contains(.hideMenuBar) || options.contains(.autoHideMenuBar)
                isMenuBarHiddenBySystem = hidden
            }
            .store(in: &c)

        if
            let hiddenSection = section(withName: .alwaysHidden),
            let window = hiddenSection.controlItem.window
        {
            window.publisher(for: \.frame)
                .map(\.origin.y)
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard
                        let self,
                        let isMenuBarHidden = Defaults.globalDomain["_HIHideMenuBar"] as? Bool
                    else {
                        return
                    }
                    isMenuBarHiddenBySystemUserDefaults = isMenuBarHidden
                }
                .store(in: &c)
        }

        // Handle the `focusedApp` and `smart` rehide strategies.
        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didActivateApplicationNotification
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] notification in
            let activatedApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            guard
                let self,
                let appState,
                appState.settings.general.autoRehide,
                Self.shouldHandleAutoRehideActivation(
                    activatedProcessIdentifier: activatedApplication?.processIdentifier,
                    currentProcessIdentifier: ProcessInfo.processInfo.processIdentifier
                )
            else {
                if self?.appState?.settings.general.autoRehide == false {
                    // Auto-rehide is off, so no strategy fires.
                }
                return
            }

            let strategy = appState.settings.general.rehideStrategy
            switch strategy {
            case .focusedApp, .smart:
                guard
                    let screen = appState.hidEventManager.bestScreen(appState: appState),
                    !appState.hidEventManager.isMouseInsideMenuBar(appState: appState, screen: screen),
                    !appState.hidEventManager.isMouseInsideIceBar(appState: appState)
                else {
                    return
                }
                Task { [weak self] in
                    // Wait for focus to settle and carry an activation
                    // inside the reveal grace period to its end instead
                    // of dropping that activation permanently.
                    let delay = Self.rehideDelay(for: strategy, since: self?.lastShowTimestamp)
                    guard await (try? Task.sleep(for: delay)) != nil else { return }

                    guard let self else { return }
                    guard appState.settings.general.rehideStrategy == strategy else { return }
                    if strategy == .smart, await appState.itemManager.isAnyMenuBarItemMenuOpen() {
                        return
                    }

                    self.hideVisibleSections()
                }
            default:
                break
            }
        }
        .store(in: &c)

        appState?.publisherForWindow(.settings)
            .sink { [weak self] window in
                self?.settingsWindow = window
            }
            .store(in: &c)

        if let appState {
            let displaySettings = appState.settings.displaySettings
            displayConfigurationsObservationTask = Task { [weak self] in
                let changes = Observations { displaySettings.configurations }
                for await _ in changes {
                    guard let self else { return }
                    updateControlItemStates()
                }
            }

            // Rebuild per-item hotkeys so new items become assignable.
            // Debounced to avoid churning registrations on every cache tick.
            let itemManager = appState.itemManager
            itemCacheHotkeyObservationTask = Task { [weak self] in
                let changes = Observations { itemManager.itemCache }
                for await _ in changes.debounce(for: .seconds(0.5)) {
                    guard let self else { return }
                    rebuildItemHotkeys()
                }
            }

            let general = appState.settings.general
            hideDockIconWhenTogglingObservationTask = Task { [weak self] in
                let changes = Observations { general.hideDockIconWhenToggling }
                for await hideDockIcon in changes {
                    guard let self else { return }
                    reconcileAutomaticApplicationMenuHide(hideDockIconWhenToggling: hideDockIcon)
                }
            }
        }

        settingsWindowObservationTask = Task { [weak self] in
            let changes = Observations { self?.settingsWindow }
            for await window in changes {
                guard let self else { return }
                guard let window else { continue }
                settingsWindowVisibilityCancellable = window.publisher(for: \.isVisible)
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] isVisible in
                        guard let self else { return }
                        if isVisible {
                            updateAverageColorInfo()
                            // macOS no longer posts a wallpaper change notification.
                            averageColorRefreshCancellable = Timer.publish(every: 60, tolerance: 10, on: .main, in: .default)
                                .autoconnect()
                                .sink { [weak self] _ in
                                    self?.updateAverageColorInfo()
                                }
                        } else {
                            averageColorRefreshCancellable?.cancel()
                            averageColorRefreshCancellable = nil
                        }
                    }
            }
        }

        // Refresh average color when space or screen changes while settings or adaptive is active.
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
                .replace(with: ()),
            NotificationCenter.default
                .publisher(for: NSApplication.didChangeScreenParametersNotification)
                .replace(with: ())
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            guard let self else { return }
            guard settingsWindow?.isVisible == true || adaptiveCaptureRequirements?.isAdaptive == true else { return }
            updateAverageColorInfo()
        }
        .store(in: &c)

        // Cache colors before sleep to avoid a white flash on wake.
        // screensDidSleep/Wake also fire for system sleep (lid close).
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.screensDidSleepNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                sleepColorCache = averageColors
                areDisplaysAsleep = true
            }
            .store(in: &c)

        // On wake, restore cached colors, then poll every 1s until the color
        // changes and holds for two captures, or 10s max.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                areDisplaysAsleep = false
                guard adaptiveCaptureRequirements?.isAdaptive == true else { return }

                guard let cache = sleepColorCache else {
                    updateAverageColorInfo()
                    return
                }

                // A new pass stamp drops any capture still in flight from
                // before the sleep, so it can't overwrite the restore.
                captureGeneration += 1
                averageColors = cache
                if let id = NSScreen.screenWithActiveMenuBar?.displayID,
                   let cached = cache[id]
                {
                    averageColorInfo = cached
                }

                wakePollPrevColors = nil
                wakePollStableCount = 0
                wakePollDidChange = false
                wakePollStartTime = Date()
                wakePollTimer = Timer.publish(every: 1, on: .main, in: .default)
                    .autoconnect()
                    .sink { [weak self] _ in
                        guard let self else { return }
                        // Await the capture so the read below sees fresh values.
                        Task { [weak self] in
                            guard let self else { return }
                            let elapsed = wakePollStartTime.map { Date().timeIntervalSince($0) } ?? 0

                            if elapsed >= 10 {
                                sleepColorCache = nil
                                wakePollTimer = nil
                                return
                            }

                            await updateAverageColorInfoAsync()
                            let after = averageColors

                            if !wakePollDidChange, let cache = sleepColorCache, after != cache {
                                wakePollDidChange = true
                            }

                            if wakePollDidChange {
                                if let prev = wakePollPrevColors, prev == after {
                                    wakePollStableCount += 1
                                    if wakePollStableCount >= 1 {
                                        sleepColorCache = nil
                                        wakePollTimer = nil
                                        return
                                    }
                                } else {
                                    wakePollStableCount = 0
                                }
                            }

                            wakePollPrevColors = after
                        }
                    }
            }
            .store(in: &c)

        // Start/stop adaptive color refresh when background or tint uses adaptive mode.
        if let appState {
            appearanceConfigurationObservationTask?.cancel()
            appearanceConfigurationObservationTask = Task { [weak self, weak appState] in
                var previousRequirements: AdaptiveCaptureRequirements?
                // Effective configuration, so the gates follow per-Space overrides.
                let changes = Observations { appState?.appearanceManager.effectiveConfiguration }
                for await config in changes {
                    guard let self else { return }
                    guard let config else { continue }
                    let requirements = AdaptiveCaptureRequirements(configuration: config.current)
                    let action = Self.adaptiveRefreshAction(from: previousRequirements, to: requirements)
                    previousRequirements = requirements
                    switch action {
                    case .unchanged:
                        continue
                    case .recapture:
                        // What to sample changed (e.g. the gradient tint needs
                        // a palette); don't wait for the 30-second poll.
                        captureAdaptiveColorWithRetry()
                    case .start:
                        captureAdaptiveColorWithRetry()
                        adaptiveColorRefreshCancellable = Timer.publish(every: 30, tolerance: 5, on: .main, in: .default)
                            .autoconnect()
                            .sink { [weak self] _ in
                                self?.updateAverageColorInfo()
                            }
                        // Keep the timer: dynamic and aerial wallpapers change
                        // without touching the index the monitor watches.
                        wallpaperChangeMonitor.onChange = { [weak self] in
                            self?.captureAdaptiveColorWithRetry()
                        }
                        wallpaperChangeMonitor.start()
                    case .stop:
                        adaptiveColorRefreshCancellable?.cancel()
                        adaptiveColorRefreshCancellable = nil
                        wallpaperChangeMonitor.stop()
                    }
                }
            }

            // Surface a hidden item blinking for attention by showing its
            // section, never by moving it: a wrong heuristic move persists
            // (#958, #960), while the rehide timer undoes a show.
            attentionObservationTask?.cancel()
            attentionObservationTask = Task { [weak self, weak appState] in
                var previous: Set<MenuBarItemTag> = []
                let changes = Observations { appState?.imageCache.tagsSeekingAttention }
                for await tags in changes {
                    guard let self, let appState, let tags else { continue }
                    defer { previous = tags }
                    let newlySeeking = tags.subtracting(previous)
                    guard !newlySeeking.isEmpty else { continue }
                    guard Defaults.bool(forKey: .surfaceItemsSeekingAttention) else { continue }
                    // Zen mode wins. History is kept so the item surfaces
                    // later with zen mode off.
                    guard !isZenModeActive else { continue }

                    for tag in newlySeeking {
                        // Look up regardless of isHidden: the first show()
                        // would otherwise skip clearing sibling tags' records.
                        guard let section = concealingSection(containing: tag, in: appState) else {
                            continue
                        }
                        if section.isHidden {
                            diagLog.info(
                                "Surfacing \(section.name.logString) for an item seeking attention"
                            )
                            section.show()
                        }
                        // So the same blink can't re-show on every capture.
                        appState.imageCache.clearAttention(for: tag)
                    }
                }
            }
        }

        Publishers.MergeMany(sections.map(\.controlItem.$state))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let appState else {
                    return
                }

                // Don't continue if:
                //   * Hiding application menus isn't allowed (Advanced
                //     setting off, or the Dock-icon setting on).
                //   * Using the Thaw Bar.
                //   * The menu bar is hidden by the system.
                //   * The active space is fullscreen.
                //   * The settings window is visible.
                guard
                    MenuBarSection.allowsHidingApplicationMenus(
                        hideApplicationMenus: appState.settings.advanced.hideApplicationMenus,
                        hideDockIconWhenToggling: appState.settings.general.hideDockIconWhenToggling
                    ),
                    !appState.settings.displaySettings.configurationForActiveDisplay().useIceBar,
                    !isMenuBarHiddenBySystem,
                    !appState.activeSpace.isFullscreen,
                    !appState.navigationState.isSettingsPresented
                else {
                    return
                }

                let hiddenSection = self.section(withName: .hidden)
                let alwaysHiddenSection = self.section(withName: .alwaysHidden)

                // A section in the Thaw Bar expands nothing inline. This covers
                // useThawBarForAlwaysHidden, where only one section is inline.
                let panelSection = iceBarPanel.currentSection
                let isShowingHiddenSection = (hiddenSection.map { !$0.isHidden } ?? false)
                    && panelSection != .hidden
                let isShowingAlwaysHiddenSection = (alwaysHiddenSection.map { !$0.isHidden } ?? false)
                    && panelSection != .alwaysHidden

                if isShowingHiddenSection || isShowingAlwaysHiddenSection {
                    guard let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main else {
                        return
                    }

                    Task {
                        // The window server needs time to update window positions after expansion.
                        try? await Task.sleep(for: .milliseconds(50))

                        guard let appMenuFrame = screen.getApplicationMenuFrame() else {
                            return
                        }

                        let allItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)

                        // Items on this screen share the app menu's Y.
                        let menuBarY = appMenuFrame.origin.y
                        let screenItems = allItems.filter { item in
                            abs(item.bounds.origin.y - menuBarY) < 50
                        }

                        let hiddenControlItem = screenItems.first { $0.tag == .hiddenControlItem }
                        let alwaysHiddenControlItem = screenItems.first { $0.tag == .alwaysHiddenControlItem }

                        // Approximate hidden items width from control item positions.

                        var controlBounds: CGRect = .zero
                        var hiddenItemsWidth: CGFloat = 0

                        if isShowingAlwaysHiddenSection, let ahControl = alwaysHiddenControlItem {
                            controlBounds = ahControl.bounds
                            if let appState = self.appState {
                                hiddenItemsWidth = appState.itemManager.itemCache[.alwaysHidden].reduce(0) { $0 + $1.bounds.width }
                            }
                        } else if isShowingHiddenSection, let hControl = hiddenControlItem {
                            controlBounds = hControl.bounds
                            if let appState = self.appState {
                                hiddenItemsWidth = appState.itemManager.itemCache[.hidden].reduce(0) { $0 + $1.bounds.width }
                            }
                        }

                        // The hidden items replace the control item when expanded.
                        let newRightmostPos = controlBounds.minX + hiddenItemsWidth

                        let appMenuRightStart = appMenuFrame.maxX

                        let spaceAvailableFromAppMenuEnd: CGFloat = if let notch = screen.frameOfNotch {
                            if appMenuRightStart > notch.minX {
                                // Items get moved past the notch.
                                (notch.minX - appMenuRightStart) + (screen.visibleFrame.maxX - notch.maxX)
                            } else {
                                screen.visibleFrame.maxX - appMenuRightStart
                            }
                        } else {
                            screen.visibleFrame.maxX - appMenuRightStart
                        }

                        let spaceNeededFromAppMenuEnd = newRightmostPos - appMenuRightStart

                        if spaceNeededFromAppMenuEnd > spaceAvailableFromAppMenuEnd {
                            self.hideApplicationMenus()
                        }
                    }
                } else if isHidingApplicationMenus, !isManuallyHidingApplicationMenus {
                    showApplicationMenus()
                }
            }
            .store(in: &c)

        cancellables = c
    }

    // MARK: - Adaptive Color Capture

    /// What an appearance configuration needs sampled from the screen.
    ///
    /// One value, so the observer can tell a switch between adaptive kinds
    /// from a switch in or out of adaptive mode.
    nonisolated struct AdaptiveCaptureRequirements: Equatable {
        /// Whether the average color of the menu bar strip is needed.
        let needsAverageColor: Bool

        /// Whether a palette of the wallpaper's dominant colors is needed.
        let needsPalette: Bool

        /// Whether the configuration samples the wallpaper at all.
        var isAdaptive: Bool {
            needsAverageColor || needsPalette
        }

        init(configuration: MenuBarAppearancePartialConfiguration) {
            needsAverageColor = configuration.backgroundKind == .adaptive || configuration.tintKind.isAdaptive
            needsPalette = configuration.tintKind == .adaptiveGradient
        }
    }

    /// What the observer of the effective configuration does with the adaptive
    /// color refresh when the configuration changes.
    nonisolated enum AdaptiveRefreshAction: Equatable {
        /// Leave the refresh as it is; the new configuration samples exactly
        /// what the previous one did.
        case unchanged
        /// Start the refresh: capture, then poll and watch the wallpaper.
        case start
        /// Keep the running refresh, but capture now, because what has to be
        /// sampled changed.
        case recapture
        /// Stop the refresh.
        case stop
    }

    /// Returns the refresh work a change in capture requirements calls for.
    static nonisolated func adaptiveRefreshAction(
        from previous: AdaptiveCaptureRequirements?,
        to current: AdaptiveCaptureRequirements
    ) -> AdaptiveRefreshAction {
        guard previous != current else {
            return .unchanged
        }
        guard current.isAdaptive else {
            return .stop
        }
        return previous?.isAdaptive == true ? .recapture : .start
    }

    /// What the configuration the overlays actually render needs sampled, or
    /// `nil` without app state to resolve it from.
    ///
    /// Uses the effective configuration, so a per-Space override that turns
    /// on adaptive color gets its samples.
    private var adaptiveCaptureRequirements: AdaptiveCaptureRequirements? {
        guard let appState else { return nil }
        return AdaptiveCaptureRequirements(
            configuration: appState.appearanceManager.effectiveConfiguration.current
        )
    }

    /// Updates the ``averageColorInfo`` and ``averageColors`` properties with
    /// the current average color of the menu bar background per screen.
    ///
    /// Fire-and-forget. Callers that read the result must await
    /// updateAverageColorInfoAsync instead.
    func updateAverageColorInfo() {
        Task { [weak self] in
            await self?.updateAverageColorInfoAsync()
        }
    }

    /// Awaitable variant; all writes are done when it returns. A pass
    /// overtaken by a newer one publishes nothing, so a read can still be
    /// incomplete while the newer pass is in flight.
    func updateAverageColorInfoAsync() async {
        guard let appState, !areDisplaysAsleep else { return }

        let isSettingsVisible = settingsWindow?.isVisible == true
        let isIceBarVisible = appState.navigationState.isIceBarPresented
        let isSearchVisible = appState.navigationState.isSearchPresented
        let anyIceBarEnabled = appState.settings.displaySettings.isIceBarEnabledOnAnyDisplay
        let requirements = AdaptiveCaptureRequirements(
            configuration: appState.appearanceManager.effectiveConfiguration.current
        )
        let isAdaptiveActive = requirements.isAdaptive

        guard isSettingsVisible || isIceBarVisible || isSearchVisible || anyIceBarEnabled || isAdaptiveActive else {
            return
        }

        let targetScreens: [NSScreen]
        if isAdaptiveActive {
            targetScreens = NSScreen.screens
        } else if isSettingsVisible {
            targetScreens = [settingsWindow?.screen].compactMap(\.self)
        } else {
            guard let screen = NSScreen.screenWithActiveMenuBar else { return }
            targetScreens = [screen]
        }

        guard !targetScreens.isEmpty else { return }

        let windows = WindowInfo.createWindows(option: .onScreen)
        let activeDisplayID = NSScreen.screenWithActiveMenuBar?.displayID

        var inputs = [(displayID: CGDirectDisplayID, windowIDs: [CGWindowID], bounds: CGRect, fullBounds: CGRect)]()
        for screen in targetScreens {
            let displayID = screen.displayID
            guard
                let menuBarWindow = WindowInfo.menuBarWindow(from: windows, for: displayID),
                let wallpaperWindow = WindowInfo.wallpaperWindow(from: windows, for: displayID)
            else {
                continue
            }
            let windowIDs = [menuBarWindow.windowID, wallpaperWindow.windowID]
            let bounds = withMutableCopy(of: wallpaperWindow.bounds) { $0.size.height = 1 }
            inputs.append((displayID, windowIDs, bounds, wallpaperWindow.bounds))
        }

        let needsPalette = requirements.needsPalette

        // Several passes can be in flight; a slow one must not publish over
        // a newer one.
        captureGeneration += 1
        let generation = captureGeneration

        await withTaskGroup(of: (CGDirectDisplayID, MenuBarAverageColorInfo, WallpaperPalette?)?.self) { group in
            for input in inputs {
                group.addTask {
                    // Displays can sleep mid-pass; each capture rechecks.
                    guard
                        await !self.areDisplaysAsleep,
                        let image = await ScreenCapture.captureWindowsAsync(
                            with: input.windowIDs,
                            screenBounds: input.bounds,
                            option: .nominalResolution
                        ),
                        let color = image.averageColor(option: .ignoreAlpha)
                    else {
                        return nil
                    }

                    var palette: WallpaperPalette?
                    if needsPalette, await !self.areDisplaysAsleep {
                        // A one-pixel strip is too little for a palette, so
                        // re-capture at the wallpaper's full height.
                        palette = await ScreenCapture.captureWindowsAsync(
                            with: input.windowIDs,
                            screenBounds: input.fullBounds,
                            option: .nominalResolution
                        )?.dominantColors()
                    }

                    return (
                        input.displayID,
                        MenuBarAverageColorInfo(color: color, source: .menuBarWindow),
                        palette
                    )
                }
            }

            for await result in group {
                // A newer pass has taken over; drain without publishing.
                guard captureGeneration == generation else { continue }
                guard let (displayID, info, palette) = result else { continue }
                if averageColors[displayID] != info {
                    averageColors[displayID] = info
                }
                if displayID == activeDisplayID, averageColorInfo != info {
                    averageColorInfo = info
                }
                // Keep the previous palette on a failed or empty capture, so
                // a momentary miss doesn't drop the tint.
                if let palette, palette.primary != nil, wallpaperPalettes[displayID] != palette {
                    wallpaperPalettes[displayID] = palette
                }
            }
        }
    }

    /// Retries until every screen has what the configuration renders from,
    /// e.g. while WindowServer is still settling at launch.
    private func captureAdaptiveColorWithRetry() {
        Task { [weak self] in
            guard let self else { return }
            for attempt in 0 ..< 10 {
                if attempt > 0 {
                    try? await Task.sleep(for: .seconds(1))
                }
                await self.updateAverageColorInfoAsync()
                if self.hasCompleteAdaptiveCapture() {
                    return
                }
            }
        }
    }

    /// Returns a Boolean value that indicates whether every screen holds the
    /// samples the current configuration needs.
    ///
    /// The palette capture can fail on its own, so a color alone isn't
    /// complete.
    private func hasCompleteAdaptiveCapture() -> Bool {
        guard let requirements = adaptiveCaptureRequirements else {
            return true
        }
        return NSScreen.screens.allSatisfy { screen in
            let displayID = screen.displayID
            guard averageColors.keys.contains(displayID) else {
                return false
            }
            return !requirements.needsPalette || wallpaperPalettes[displayID]?.primary != nil
        }
    }

    /// Returns a Boolean value that indicates whether the given display
    /// has a valid menu bar.
    func hasValidMenuBar(in windows: [WindowInfo], for display: CGDirectDisplayID) -> Bool {
        guard
            let window = WindowInfo.menuBarWindow(from: windows, for: display),
            let element = AXHelpers.element(at: window.bounds.origin)
        else {
            return false
        }
        return AXHelpers.role(for: element) == .menuBar
    }

    /// Shows the secondary context menu.
    func showSecondaryContextMenu(at point: CGPoint) {
        let menu = NSMenu(title: "\(Constants.displayName)")

        let editAppearanceItem = NSMenuItem(
            title: String(localized: "Edit Menu Bar Appearance…"),
            action: #selector(showAppearanceEditorPanel),
            keyEquivalent: ""
        )
        editAppearanceItem.image = NSImage(systemSymbolName: "swatchpalette", accessibilityDescription: "Edit Appearance")
        editAppearanceItem.target = self
        menu.addItem(editAppearanceItem)

        let editLayoutItem = NSMenuItem(
            title: String(localized: "Edit Menu Bar Layout…"),
            action: #selector(showLayoutEditorPanel),
            keyEquivalent: ""
        )
        editLayoutItem.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Edit Layout")
        editLayoutItem.target = self
        menu.addItem(editLayoutItem)

        if let appState, !appState.profileManager.profiles.isEmpty {
            menu.addItem(.separator())

            let profilesItem = NSMenuItem(
                title: String(localized: "Profiles"),
                action: nil,
                keyEquivalent: ""
            )
            profilesItem.image = NSImage(
                systemSymbolName: "person.crop.rectangle.stack",
                accessibilityDescription: "Profiles"
            )
            let profilesMenu = NSMenu()
            for meta in appState.profileManager.profiles {
                let item = NSMenuItem(
                    title: meta.name,
                    action: #selector(applyProfileFromMenu(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = meta.id
                if meta.id == appState.profileManager.activeProfileID {
                    item.state = .on
                }
                profilesMenu.addItem(item)
            }
            profilesItem.submenu = profilesMenu
            menu.addItem(profilesItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: String(localized: "\(Constants.displayName) Settings…"),
            action: #selector(AppDelegate.openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: "Settings")
        menu.addItem(settingsItem)

        if appState?.settings.advanced.enableSecondaryContextMenuQuit == true {
            menu.addItem(.separator())

            let quitItem = NSMenuItem(
                title: String(localized: "Quit \(Constants.displayName)"),
                action: #selector(quitFromSecondaryContextMenu),
                keyEquivalent: "q"
            )
            quitItem.keyEquivalentModifierMask = .command
            quitItem.target = self
            quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
            menu.addItem(quitItem)

            let restartItem = NSMenuItem(
                title: String(localized: "Restart \(Constants.displayName)"),
                action: #selector(restartFromSecondaryContextMenu),
                keyEquivalent: "q"
            )
            restartItem.keyEquivalentModifierMask = [.command, .option]
            restartItem.isAlternate = true
            restartItem.target = self
            restartItem.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Restart")
            menu.addItem(restartItem)
        }

        menu.popUp(positioning: nil, at: point, in: nil)
    }

    @objc private func quitFromSecondaryContextMenu() {
        // Terminate only in .default mode, after popUp's tracking loop and its
        // Task unwind, so applicationShouldTerminate's Tasks can drain.
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated {
                NSApp.terminate(nil)
            }
        }
    }

    @objc private func restartFromSecondaryContextMenu() {
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated {
                self?.appState?.restartSelf()
            }
        }
    }

    @objc private func applyProfileFromMenu(_ menuItem: NSMenuItem) {
        guard
            let profileID = menuItem.representedObject as? UUID,
            let appState,
            appState.profileManager.layoutTask == nil,
            profileID != appState.profileManager.activeProfileID
        else { return }
        Task { [weak self] in
            do {
                let profile = try appState.profileManager.loadProfile(id: profileID)
                let previousID = appState.profileManager.activeProfileID
                appState.profileManager.activeProfileID = profileID
                appState.profileManager.applyProfile(profile, to: appState, previousProfileID: previousID)
            } catch {
                self?.diagLog.error("Failed to apply profile \(profileID): \(error)")
            }
        }
    }

    /// Chooses the activation policy used while hiding application menus.
    ///
    /// Hiding menus needs `.regular`, which shows the Dock icon. With the
    /// clean-Dock setting stay `.accessory`, unless explicit UI already asked
    /// for `.regular`.
    static nonisolated func activationPolicyForHidingApplicationMenus(
        hideDockIconWhenToggling: Bool,
        explicitUIWantsRegularActivation: Bool,
        isManualToggle: Bool = false
    ) -> NSApplication.ActivationPolicy {
        if explicitUIWantsRegularActivation || isManualToggle {
            return .regular
        }
        return hideDockIconWhenToggling ? .accessory : .regular
    }

    /// How an in-flight automatic hide should react when the Dock-icon
    /// setting changes.
    nonisolated enum AutomaticHideReconcileAction: Equatable {
        /// Leave the current hide state alone.
        case none
        /// Restore application menus and accessory activation.
        case restoreApplicationMenus
        /// Drop automatic-hide bookkeeping without changing policy, because
        /// explicit UI is already regular.
        case clearAutomaticHideState
    }

    /// Automatic overflow hiding must not survive turning on
    /// ``GeneralSettings/hideDockIconWhenToggling``. A manual hide-menus
    /// command is left alone. Settings and other explicit UI keep `.regular`.
    static nonisolated func automaticHideReconcileAction(
        hideDockIconWhenToggling: Bool,
        isHidingApplicationMenus: Bool,
        isManuallyHidingApplicationMenus: Bool,
        explicitUIWantsRegularActivation: Bool
    ) -> AutomaticHideReconcileAction {
        guard hideDockIconWhenToggling, isHidingApplicationMenus, !isManuallyHidingApplicationMenus else {
            return .none
        }
        return explicitUIWantsRegularActivation ? .clearAutomaticHideState : .restoreApplicationMenus
    }

    /// Cancels a pending accessory retry so a later `.regular` activation
    /// cannot be overwritten. No-op when the pending hide itself requested
    /// `.regular`, because that path must keep its 25 ms force-activation retry.
    func invalidatePendingAccessoryActivation() {
        guard pendingHideActivationIsAccessory else { return }
        cancelHideApplicationMenusActivationTask()
    }

    /// Hides the application menus.
    ///
    /// - Important: Uses `.regular` activation, which briefly shows the Dock
    ///   icon; a manual toggle always does. With
    ///   ``GeneralSettings/hideDockIconWhenToggling`` on, a non-manual call
    ///   stays `.accessory` unless explicit UI already requested `.regular`.
    func hideApplicationMenus(manual: Bool = false) {
        guard let appState else {
            diagLog.error("Error hiding application menus: Missing app state")
            return
        }

        if isHidingApplicationMenus {
            return
        }

        diagLog.info("Hiding application menus")
        isHidingApplicationMenus = true
        if manual {
            isManuallyHidingApplicationMenus = true
        }

        cancelHideApplicationMenusActivationTask()
        let hideDockIcon = appState.settings.general.hideDockIconWhenToggling
        let policy = Self.activationPolicyForHidingApplicationMenus(
            hideDockIconWhenToggling: hideDockIcon,
            explicitUIWantsRegularActivation: explicitUIWantsRegularActivation(
                hideDockIconWhenToggling: hideDockIcon
            ),
            isManualToggle: manual
        )
        pendingHideActivationIsAccessory = policy == .accessory
        hideApplicationMenusActivationTask = Task { @MainActor in
            guard isHidingApplicationMenus else { return }

            appState.activate(withPolicy: policy)

            // The first activation after a policy change can be ignored.
            try? await Task.sleep(for: .milliseconds(25))
            guard !Task.isCancelled, isHidingApplicationMenus else { return }
            let retryHideDockIcon = appState.settings.general.hideDockIconWhenToggling
            let retryPolicy = Self.activationPolicyForHidingApplicationMenus(
                hideDockIconWhenToggling: retryHideDockIcon,
                explicitUIWantsRegularActivation: explicitUIWantsRegularActivation(
                    hideDockIconWhenToggling: retryHideDockIcon
                ),
                isManualToggle: manual
            )
            pendingHideActivationIsAccessory = retryPolicy == .accessory
            appState.activate(withPolicy: retryPolicy)
        }
    }

    func showApplicationMenus() {
        cancelHideApplicationMenusActivationTask()
        guard let appState else {
            diagLog.error("Error showing application menus: Missing app state")
            return
        }
        diagLog.info("Showing application menus")
        appState.deactivate(withPolicy: .accessory)
        isHidingApplicationMenus = false
        isManuallyHidingApplicationMenus = false
    }

    func toggleApplicationMenus() {
        if isHidingApplicationMenus {
            showApplicationMenus()
        } else {
            hideApplicationMenus(manual: true)
        }
    }

    /// Clears an in-flight automatic hide when the Dock-icon setting turns on.
    private func reconcileAutomaticApplicationMenuHide(hideDockIconWhenToggling: Bool) {
        switch Self.automaticHideReconcileAction(
            hideDockIconWhenToggling: hideDockIconWhenToggling,
            isHidingApplicationMenus: isHidingApplicationMenus,
            isManuallyHidingApplicationMenus: isManuallyHidingApplicationMenus,
            explicitUIWantsRegularActivation: explicitUIWantsRegularActivation(
                hideDockIconWhenToggling: hideDockIconWhenToggling
            )
        ) {
        case .none:
            return
        case .restoreApplicationMenus:
            showApplicationMenus()
        case .clearAutomaticHideState:
            cancelHideApplicationMenusActivationTask()
            isHidingApplicationMenus = false
            isManuallyHidingApplicationMenus = false
        }
    }

    private func cancelHideApplicationMenusActivationTask() {
        hideApplicationMenusActivationTask?.cancel()
        hideApplicationMenusActivationTask = nil
        pendingHideActivationIsAccessory = false
    }

    /// Settings, permissions, search, and the Thaw Bar activate as regular.
    /// The current policy covers the 25 ms before their flags catch up.
    private func explicitUIWantsRegularActivation(hideDockIconWhenToggling: Bool) -> Bool {
        guard let appState else { return false }
        if appState.explicitUIWantsRegularActivation {
            return true
        }
        return hideDockIconWhenToggling && NSApp.activationPolicy() == .regular
    }

    // MARK: - Zen Mode

    /// Whether zen mode is currently active. While active, every concealable
    /// section stays hidden and hover reveal is locked off.
    private(set) var isZenModeActive = false

    /// The sections that were revealed when zen mode was engaged, restored on
    /// exit. Session-only: zen mode never survives an app relaunch.
    private var sectionsRevealedBeforeZenMode: Set<MenuBarSection.Name> = []

    /// Restored on exit, so a hotkey reveal's hover lock isn't released early.
    private var showOnHoverAllowedBeforeZenMode = true

    /// Conceals the hidden sections and locks reveal gestures, then restores
    /// what was showing. Never moves items, so it can't disturb ordering.
    func toggleZenMode() {
        // An explicit toggle outlives the end of a presentation.
        isZenModeEngagedAutomatically = false
        if isZenModeActive {
            deactivateZenMode()
        } else {
            activateZenMode()
        }
    }

    /// Only an automatic engagement is automatically withdrawn.
    private var isZenModeEngagedAutomatically = false

    /// Engages or withdraws zen mode on the monitor's behalf.
    ///
    /// Idempotent: the monitor re-evaluates rather than tracking edges.
    func setAutomaticZenMode(_ isActive: Bool) {
        if isActive {
            guard !isZenModeActive else { return }
            activateZenMode()
            isZenModeEngagedAutomatically = true
        } else {
            guard isZenModeActive, isZenModeEngagedAutomatically else { return }
            deactivateZenMode()
            isZenModeEngagedAutomatically = false
        }
    }

    private func activateZenMode() {
        // Before the hides, since each hide() re-enables hover reveal.
        showOnHoverAllowedBeforeZenMode = showOnHoverAllowed
        var revealedNames = Set<MenuBarSection.Name>()
        for name in [MenuBarSection.Name.hidden, .alwaysHidden] {
            guard let section = section(withName: name), section.isEnabled else {
                continue
            }
            if !section.isHidden {
                revealedNames.insert(name)
                section.hide()
            }
        }
        sectionsRevealedBeforeZenMode = revealedNames
        // Each hide() runs resetClosedPresentationState, which re-enables
        // hover reveal; set the lock after all hides so it sticks.
        showOnHoverAllowed = false
        isZenModeActive = true
    }

    private func deactivateZenMode() {
        isZenModeActive = false
        showOnHoverAllowed = showOnHoverAllowedBeforeZenMode
        showOnHoverAllowedBeforeZenMode = true
        for name in sectionsRevealedBeforeZenMode {
            section(withName: name)?.show()
        }
        sectionsRevealedBeforeZenMode = []
    }

    @objc private func showLayoutEditorPanel() {
        guard let screen = MenuBarLayoutEditorPanel.defaultScreen else {
            return
        }
        layoutEditorPanel.show(on: screen) {
            self.dismissLayoutEditorPanel()
        }
    }

    func dismissLayoutEditorPanel() {
        layoutEditorPanel.close()
    }

    @objc private func showAppearanceEditorPanel() {
        guard let screen = MenuBarAppearanceEditorPanel.defaultScreen else {
            return
        }
        appearanceEditorPanel.show(on: screen) {
            self.dismissAppearanceEditorPanel()
        }
    }

    /// Dismisses the appearance editor panel if it is shown.
    func dismissAppearanceEditorPanel() {
        appearanceEditorPanel.close()
    }

    func updateLastShowTimestamp() {
        lastShowTimestamp = .now
    }

    /// Delay for a focus-change rehide. A focus change during the reveal
    /// grace period is deferred to the end of that period rather than lost.
    /// Smart waits longer for focus to settle than focusedApp because it
    /// re-checks state (open menus) that a fresh activation can still churn.
    static nonisolated func rehideDelay(
        for strategy: RehideStrategy,
        since lastShow: ContinuousClock.Instant?,
        now: ContinuousClock.Instant = .now
    ) -> Duration {
        let focusSettleDelay: Duration = strategy == .smart
            ? .milliseconds(250)
            : .milliseconds(100)
        guard let lastShow else { return focusSettleDelay }
        let remainingGrace = Duration.milliseconds(500) - lastShow.duration(to: now)
        return max(focusSettleDelay, remainingGrace)
    }

    /// Thaw temporarily activates itself when it must hide application menus.
    /// That internal activation is not a user focus change and must not rehide
    /// the section that caused it.
    static nonisolated func shouldHandleAutoRehideActivation(
        activatedProcessIdentifier: pid_t?,
        currentProcessIdentifier: pid_t
    ) -> Bool {
        activatedProcessIdentifier != currentProcessIdentifier
    }

    private func hideVisibleSections() {
        for section in sections where !section.isHidden {
            section.hide()
        }
    }

    /// Updates the control item states for all sections.
    ///
    /// - Parameter screen: The screen to use for the update. If `nil`, the
    ///   best screen is determined automatically.
    func updateControlItemStates(for screen: NSScreen? = nil) {
        for section in sections {
            section.updateControlItemState(for: screen)
        }
    }

    /// The hidden or always-hidden section whose cache holds `tag`, whether
    /// or not it is shown.
    private func concealingSection(
        containing tag: MenuBarItemTag,
        in appState: AppState
    ) -> MenuBarSection? {
        for name in [MenuBarSection.Name.hidden, .alwaysHidden] {
            guard appState.itemManager.itemCache[name].contains(where: { $0.tag == tag }) else {
                continue
            }
            return section(withName: name)
        }
        return nil
    }

    func section(withName name: MenuBarSection.Name) -> MenuBarSection? {
        sections.first { $0.name == name }
    }

    func controlItem(withName name: MenuBarSection.Name) -> ControlItem? {
        section(withName: name)?.controlItem
    }

    // MARK: - Per-Item Hotkeys

    /// Creates and reconciles the per-item hotkeys, then observes their changes.
    ///
    /// Incremental, so a cache tick doesn't tear down live registrations.
    /// Covers present items plus saved bindings, so a binding survives its
    /// app quitting.
    func rebuildItemHotkeys() {
        guard let appState else { return }

        let saved = Defaults.dictionary(forKey: .menuBarItemHotkeys) as? [String: Data] ?? [:]
        let dec = JSONDecoder()
        let enc = JSONEncoder()

        // Skip control items and unresolved items, whose UUID is unstable.
        let presentIdentifiers = Set(
            appState.itemManager.itemCache.managedItems
                .filter { !$0.isControlItem && $0.sourcePID != nil }
                .map(\.uniqueIdentifier)
        )
        let wantedIdentifiers = presentIdentifiers.union(saved.keys)

        var newHotkeys = itemHotkeys

        for (identifier, hotkey) in itemHotkeys where !wantedIdentifiers.contains(identifier) {
            hotkey.disable()
            hotkeyItemMap[ObjectIdentifier(hotkey)] = nil
            newHotkeys[identifier] = nil
        }

        for identifier in wantedIdentifiers {
            let savedCombo: KeyCombination? = saved[identifier].flatMap { data in
                try? dec.decode(KeyCombination?.self, from: data)
            }

            if let existing = newHotkeys[identifier] {
                // Only assign when it differs, to avoid a redundant write.
                if existing.keyCombination != savedCombo {
                    existing.keyCombination = savedCombo
                }
                continue
            }

            let hotkey = Hotkey(action: .openMenuBarItem)
            hotkey.performSetup(with: appState)
            hotkey.keyCombination = savedCombo
            hotkeyItemMap[ObjectIdentifier(hotkey)] = identifier

            // Assigned after the initial value so it isn't persisted again.
            hotkey.keyCombinationDidChange = { [weak self, weak hotkey] in
                guard let self, let hotkey else { return }
                var dict = Defaults.dictionary(forKey: .menuBarItemHotkeys) as? [String: Data] ?? [:]
                if let combo = hotkey.keyCombination, let data = try? enc.encode(combo) {
                    dict[identifier] = data
                } else {
                    dict.removeValue(forKey: identifier)
                }
                Defaults.set(dict, forKey: .menuBarItemHotkeys)
                self.hotkeyItemMap[ObjectIdentifier(hotkey)] = hotkey.keyCombination != nil ? identifier : nil
            }

            newHotkeys[identifier] = hotkey
        }

        itemHotkeys = newHotkeys
    }

    /// Opens the menu of the menu bar item with the given identifier.
    ///
    /// No-op if the item isn't present.
    func openItem(withIdentifier identifier: String) {
        guard let appState else { return }
        guard let item = appState.itemManager.itemCache.managedItems.first(
            where: { $0.uniqueIdentifier == identifier }
        ) else {
            diagLog.info("Cannot open menu bar item; no live item for identifier \(identifier)")
            return
        }
        let displayID = NSScreen.screenWithActiveMenuBar?.displayID
        Task {
            await appState.itemManager.activate(item: item, on: displayID)
        }
    }
}

// MARK: - MenuBarAverageColorInfo

/// Information for the average color of the menu bar.
struct MenuBarAverageColorInfo: Hashable {
    /// Sources used to compute the average color of the menu bar.
    enum Source: Hashable {
        case menuBarWindow
    }

    /// The average color of the menu bar
    var color: CGColor

    /// The source used to compute the color.
    var source: Source

    /// The brightness of the menu bar's color.
    var brightness: CGFloat {
        color.brightness ?? 0
    }

    /// A Boolean value that indicates whether the menu bar has a
    /// bright color.
    ///
    /// `true` above ``Constants.menuBarBrightnessThreshold``, where the menu
    /// bar draws its items darker.
    var isBright: Bool {
        brightness > Constants.menuBarBrightnessThreshold
    }

    /// Returns whether the menu bar has a bright color for the given screen.
    /// Uses a lower threshold for notched displays to bias toward black text.
    /// - Parameter screen: The screen to check for notch presence
    /// - Returns: `true` if the background is bright enough to require dark text
    func isBright(for screen: NSScreen?) -> Bool {
        let activeOrPassed = screen ?? NSScreen.screenWithActiveMenuBar
        let hasNotch = activeOrPassed?.hasNotch == true
        let threshold = hasNotch
            ? Constants.notchedDisplayBrightnessThreshold
            : Constants.menuBarBrightnessThreshold
        return brightness > threshold
    }
}
