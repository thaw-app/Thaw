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

    /// Diagnostic logger for the menu bar manager.
    @ObservationIgnored
    private let diagLog = DiagLog(category: "MenuBarManager")

    /// The shared app state.
    @ObservationIgnored
    private weak var appState: AppState?

    /// Storage for internal observers.
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    /// Task observing `DisplaySettingsManager.configurations`, which is
    /// `@Observable` rather than a Combine `ObservableObject`.
    private var displayConfigurationsObservationTask: Task<Void, Never>?

    /// Task observing `settingsWindow`'s `isVisible` KVO stream (wave 3),
    /// replacing the old `$settingsWindow.removeNil().map { $0.publisher(for:
    /// \.isVisible) }.switchToLatest()` pipeline. `settingsWindow` is now a
    /// plain `@Observable` property rather than a Combine `@Published` one,
    /// so it no longer has a `$settingsWindow` publisher; the inner KVO
    /// publisher on the resolved `NSWindow` is unrelated to Observation and
    /// stays Combine, manually re-subscribed on each new non-nil window
    /// value (mirroring `switchToLatest`'s behavior).
    private var settingsWindowObservationTask: Task<Void, Never>?

    /// Task observing `appearanceManager.configuration` for adaptive-color
    /// refresh start/stop (wave 3), replacing the old `$configuration.map {
    /// ... }.removeDuplicates().sink` pipeline.
    private var appearanceConfigurationObservationTask: Task<Void, Never>?

    /// Task observing `itemManager.itemCache` (wave 4), which is
    /// `@Observable` rather than a Combine `ObservableObject`, replacing the
    /// old `$itemCache.debounce(for: .seconds(0.5), scheduler:
    /// DispatchQueue.main).sink` pipeline. `Observations { }` is an
    /// `AsyncSequence`, so the debounce is reproduced with AsyncAlgorithms'
    /// `.debounce(for:)` instead.
    private var itemCacheHotkeyObservationTask: Task<Void, Never>?

    @MainActor
    deinit {
        displayConfigurationsObservationTask?.cancel()
        settingsWindowObservationTask?.cancel()
        settingsWindowVisibilityCancellable?.cancel()
        appearanceConfigurationObservationTask?.cancel()
        itemCacheHotkeyObservationTask?.cancel()
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

    /// Per-screen colors cached before sleep, restored on wake to avoid stale/white flash.
    private var sleepColorCache: [CGDirectDisplayID: MenuBarAverageColorInfo]?

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

    /// Performs the initial setup of the menu bar manager.
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

    /// Configures the internal observers for the manager.
    private func configureCancellables() {
        averageColorRefreshCancellable?.cancel()
        averageColorRefreshCancellable = nil
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
                    // Auto-rehide is off; no strategy fires. Not an error,
                    // but the user may expect focus/timed to work without
                    // the master toggle.
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

            // Refresh per-item hotkeys when the set of menu bar items changes,
            // so newly-arrived items become assignable. Debounced because the
            // item cache ticks frequently and rebuilding on every tick would
            // churn hotkey registrations.
            let itemManager = appState.itemManager
            itemCacheHotkeyObservationTask = Task { [weak self] in
                let changes = Observations { itemManager.itemCache }
                for await _ in changes.debounce(for: .seconds(0.5)) {
                    guard let self else { return }
                    rebuildItemHotkeys()
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
                            // Start a visibility-gated 60s refresh to catch wallpaper changes
                            // (macOS no longer posts a wallpaper change notification).
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
            let isAdaptiveActive: Bool = {
                guard let appState = self.appState else { return false }
                let current = appState.appearanceManager.configuration.current
                return current.backgroundKind == .adaptive || current.tintKind == .adaptive
            }()
            guard settingsWindow?.isVisible == true || isAdaptiveActive else { return }
            updateAverageColorInfo()
        }
        .store(in: &c)

        // Cache per-screen colors before display sleep so they can be restored
        // on wake, preventing a white flash before the display settles and
        // wallpaper renders. Uses screensDidSleep/Wake which fire on display
        // sleep/wake (screen lock, idle timeout) AND system sleep (lid close).
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.screensDidSleepNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                sleepColorCache = averageColors
            }
            .store(in: &c)

        // On display wake, restore pre-sleep colors immediately (no white flash),
        // then poll every 1s until the captured color changes from the cached
        // value and stabilizes (2 consecutive identical captures), or 10s max.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                let isAdaptiveActive: Bool = {
                    guard let appState = self.appState else { return false }
                    let current = appState.appearanceManager.configuration.current
                    return current.backgroundKind == .adaptive || current.tintKind == .adaptive
                }()
                guard isAdaptiveActive else { return }

                guard let cache = sleepColorCache else {
                    updateAverageColorInfo()
                    return
                }

                // Restore pre-sleep colors so the bar never flashes white.
                averageColors = cache
                if let id = NSScreen.screenWithActiveMenuBar?.displayID,
                   let cached = cache[id]
                {
                    averageColorInfo = cached
                }

                // Poll every 1s until color changes from cache then stabilizes.
                wakePollPrevColors = nil
                wakePollStableCount = 0
                wakePollDidChange = false
                wakePollStartTime = Date()
                wakePollTimer = Timer.publish(every: 1, on: .main, in: .default)
                    .autoconnect()
                    .sink { [weak self] _ in
                        guard let self else { return }
                        // Wraps the stabilization logic in a Task that awaits
                        // updateAverageColorInfoAsync so the post-capture read
                        // of averageColors sees the fresh values; the original
                        // sync call returned before the fire-and-forget Tasks
                        // populated state, defeating stabilization detection.
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
                var previousIsAdaptive: Bool?
                let changes = Observations { appState?.appearanceManager.configuration }
                for await config in changes {
                    guard let self else { return }
                    guard let config else { continue }
                    let current = config.current
                    let isAdaptive = current.backgroundKind == .adaptive || current.tintKind == .adaptive
                    guard isAdaptive != previousIsAdaptive else { continue }
                    previousIsAdaptive = isAdaptive
                    if isAdaptive {
                        captureAdaptiveColorWithRetry()
                        adaptiveColorRefreshCancellable = Timer.publish(every: 30, tolerance: 5, on: .main, in: .default)
                            .autoconnect()
                            .sink { [weak self] _ in
                                self?.updateAverageColorInfo()
                            }
                    } else {
                        adaptiveColorRefreshCancellable?.cancel()
                        adaptiveColorRefreshCancellable = nil
                    }
                }
            }
        }

        // Hide application menus when a section is shown (if applicable).
        Publishers.MergeMany(sections.map(\.controlItem.$state))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let appState else {
                    return
                }

                // Don't continue if:
                //   * The "HideApplicationMenus" setting isn't enabled.
                //   * Using the Thaw Bar.
                //   * The menu bar is hidden by the system.
                //   * The active space is fullscreen.
                //   * The settings window is visible.
                guard
                    appState.settings.advanced.hideApplicationMenus,
                    !appState.settings.displaySettings.configurationForActiveDisplay().useIceBar,
                    !isMenuBarHiddenBySystem,
                    !appState.activeSpace.isFullscreen,
                    !appState.navigationState.isSettingsPresented
                else {
                    return
                }

                // Check if hidden or alwaysHidden section is being shown
                let hiddenSection = self.section(withName: .hidden)
                let alwaysHiddenSection = self.section(withName: .alwaysHidden)

                // Use isHidden property - when section is shown, isHidden is false.
                // A section presenting in the Thaw Bar expands nothing inline,
                // so the application menus have no items to make room for. The
                // guard above already covers the display-wide setting; this
                // covers useThawBarForAlwaysHidden, where the always-hidden
                // section is in the panel while the hidden section is inline.
                let panelSection = iceBarPanel.currentSection
                let isShowingHiddenSection = (hiddenSection.map { !$0.isHidden } ?? false)
                    && panelSection != .hidden
                let isShowingAlwaysHiddenSection = (alwaysHiddenSection.map { !$0.isHidden } ?? false)
                    && panelSection != .alwaysHidden

                if isShowingHiddenSection || isShowingAlwaysHiddenSection {
                    // Use the screen with the active menu bar
                    guard let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main else {
                        return
                    }

                    Task {
                        // The window server needs time to update window positions after expansion.
                        try? await Task.sleep(for: .milliseconds(50))

                        // Get the app menu frame for this screen
                        guard let appMenuFrame = screen.getApplicationMenuFrame() else {
                            return
                        }

                        // Get ALL menu bar items
                        let allItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)

                        // Filter to items on THIS screen by comparing Y coordinate with app menu's Y
                        let menuBarY = appMenuFrame.origin.y
                        let screenItems = allItems.filter { item in
                            abs(item.bounds.origin.y - menuBarY) < 50
                        }

                        // Get the control items for this screen
                        let hiddenControlItem = screenItems.first { $0.tag == .hiddenControlItem }
                        let alwaysHiddenControlItem = screenItems.first { $0.tag == .alwaysHiddenControlItem }

                        // Approximate hidden items width from control item positions.

                        // Get control item bounds and hidden items width
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

                        // The hidden section expands by replacing control item with hidden items
                        // New rightmost = where hidden items end = control.minX + hiddenItemsWidth
                        let newRightmostPos = controlBounds.minX + hiddenItemsWidth

                        // Use the actual app menu frame for needed space
                        let appMenuRightStart = appMenuFrame.maxX

                        // Available space: if app menu extends into notch, add notch width; otherwise use visible frame
                        let spaceAvailableFromAppMenuEnd: CGFloat = if let notch = screen.frameOfNotch {
                            if appMenuRightStart > notch.minX {
                                // App menu extends into notch, items get moved past notch
                                (notch.minX - appMenuRightStart) + (screen.visibleFrame.maxX - notch.maxX)
                            } else {
                                // App menu doesn't extend into notch
                                screen.visibleFrame.maxX - appMenuRightStart
                            }
                        } else {
                            screen.visibleFrame.maxX - appMenuRightStart
                        }

                        let spaceNeededFromAppMenuEnd = newRightmostPos - appMenuRightStart

                        // If items would extend past screen edge, hide the app menu
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

    /// Updates the ``averageColorInfo`` and ``averageColors`` properties with
    /// the current average color of the menu bar background per screen.
    ///
    /// Fire-and-forget shape preserved for the call sites that don't need to
    /// read averageColors immediately after. Callers that DO need read-after
    /// semantics (captureAdaptiveColorWithRetry, the wake-poll loop) must use
    /// updateAverageColorInfoAsync directly so their read sees fresh state.
    func updateAverageColorInfo() {
        Task { [weak self] in
            await self?.updateAverageColorInfoAsync()
        }
    }

    /// Awaitable variant of updateAverageColorInfo. Per-screen captures run
    /// concurrently in a TaskGroup; the for-await loop collects results on the
    /// @MainActor context, so all averageColors / averageColorInfo writes are
    /// complete before the await returns.
    func updateAverageColorInfoAsync() async {
        guard let appState else { return }

        // Only update if we really need the color info
        let isSettingsVisible = settingsWindow?.isVisible == true
        let isIceBarVisible = appState.navigationState.isIceBarPresented
        let isSearchVisible = appState.navigationState.isSearchPresented
        let anyIceBarEnabled = appState.settings.displaySettings.isIceBarEnabledOnAnyDisplay
        let currentConfig = appState.appearanceManager.configuration.current
        let isAdaptiveActive = currentConfig.backgroundKind == .adaptive || currentConfig.tintKind == .adaptive

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

        // Resolve per-screen capture inputs synchronously on MainActor before
        // fanning out; the SCK calls themselves are the only async work.
        var inputs = [(displayID: CGDirectDisplayID, windowIDs: [CGWindowID], bounds: CGRect)]()
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
            inputs.append((displayID, windowIDs, bounds))
        }

        await withTaskGroup(of: (CGDirectDisplayID, MenuBarAverageColorInfo)?.self) { group in
            for input in inputs {
                group.addTask {
                    guard
                        let image = await ScreenCapture.captureWindowsAsync(
                            with: input.windowIDs,
                            screenBounds: input.bounds,
                            option: .nominalResolution
                        ),
                        let color = image.averageColor(option: .ignoreAlpha)
                    else {
                        return nil
                    }
                    return (input.displayID, MenuBarAverageColorInfo(color: color, source: .menuBarWindow))
                }
            }

            // Collected on @MainActor (enclosing class isolation), so the
            // averageColors / averageColorInfo writes below are safe and
            // observable to read-after callers as soon as this await returns.
            for await result in group {
                guard let (displayID, info) = result else { continue }
                if averageColors[displayID] != info {
                    averageColors[displayID] = info
                }
                if displayID == activeDisplayID, averageColorInfo != info {
                    averageColorInfo = info
                }
            }
        }
    }

    /// Attempts to capture the adaptive color with retries when the initial
    /// capture fails (e.g. during early app launch before the Window Server
    /// is fully settled). Retries until all screens have a color entry.
    private func captureAdaptiveColorWithRetry() {
        // Awaits each capture before checking averageColors so we don't burn
        // retries on stale reads of fire-and-forget Task results.
        Task { [weak self] in
            guard let self else { return }
            for attempt in 0 ..< 10 {
                if attempt > 0 {
                    try? await Task.sleep(for: .seconds(1))
                }
                await self.updateAverageColorInfoAsync()
                let allCaptured = NSScreen.screens.allSatisfy {
                    self.averageColors.keys.contains($0.displayID)
                }
                if allCaptured {
                    return
                }
            }
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

        // Profiles submenu.
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
        // Defer NSApp.terminate until the main run loop is back in default mode.
        // The action fires inside popUp's eventTracking-mode nested run loop, and
        // popUp itself was invoked from a Task that is occupying the main actor.
        // Scheduling in .default only ensures the block runs after popUp tracking
        // unwinds and the enclosing Task completes, so terminate's wait loop can
        // drain the restore and timeout Tasks scheduled by applicationShouldTerminate.
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

    /// Hides the application menus.
    ///
    /// - Important: Uses `.regular` activation policy to hide menus, which briefly shows the app in the Dock.
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

        // Ensure this happens on the main thread
        Task { @MainActor in
            guard isHidingApplicationMenus else { return }

            appState.activate(withPolicy: .regular)

            // Force activation again after a micro-delay.
            // The first activation after policy change can sometimes be ignored by the system.
            try? await Task.sleep(for: .milliseconds(25))
            guard isHidingApplicationMenus else { return }
            appState.activate()
        }
    }

    /// Shows the application menus.
    func showApplicationMenus() {
        guard let appState else {
            diagLog.error("Error showing application menus: Missing app state")
            return
        }
        diagLog.info("Showing application menus")
        appState.deactivate(withPolicy: .accessory)
        isHidingApplicationMenus = false
        isManuallyHidingApplicationMenus = false
    }

    /// Toggles the visibility of the application menus.
    func toggleApplicationMenus() {
        if isHidingApplicationMenus {
            showApplicationMenus()
        } else {
            hideApplicationMenus(manual: true)
        }
    }

    // MARK: - Zen Mode

    /// Whether zen mode is currently active. While active, every concealable
    /// section stays hidden and hover reveal is locked off.
    private(set) var isZenModeActive = false

    /// The sections that were revealed when zen mode was engaged, restored on
    /// exit. Session-only: zen mode never survives an app relaunch.
    private var sectionsRevealedBeforeZenMode: Set<MenuBarSection.Name> = []

    /// Toggles zen mode: conceals the hidden and always-hidden sections and
    /// locks reveal gestures until toggled again, then restores what was
    /// showing before. Items are never moved between sections, so engaging or
    /// leaving zen mode performs no layout writes and cannot disturb ordering.
    func toggleZenMode() {
        // An explicit toggle takes ownership away from the monitor: whatever
        // the user just asked for outlives the end of a presentation.
        isZenModeEngagedAutomatically = false
        if isZenModeActive {
            deactivateZenMode()
        } else {
            activateZenMode()
        }
    }

    /// Whether the active zen mode was engaged by ``PresentationMonitor``
    /// rather than by the user. Only an automatic engagement is automatically
    /// withdrawn, so a manual zen mode is never cancelled by unplugging a
    /// projector.
    private var isZenModeEngagedAutomatically = false

    /// Engages or withdraws zen mode on the monitor's behalf.
    ///
    /// Idempotent in both directions, because the monitor re-evaluates its
    /// signals on every display change and every poll rather than tracking
    /// edges itself.
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
        showOnHoverAllowed = true
        for name in sectionsRevealedBeforeZenMode {
            section(withName: name)?.show()
        }
        sectionsRevealedBeforeZenMode = []
    }

    /// Shows the layout editor panel.
    @objc private func showLayoutEditorPanel() {
        guard let screen = MenuBarLayoutEditorPanel.defaultScreen else {
            return
        }
        layoutEditorPanel.show(on: screen) {
            self.dismissLayoutEditorPanel()
        }
    }

    /// Dismisses the layout editor panel.
    func dismissLayoutEditorPanel() {
        layoutEditorPanel.close()
    }

    /// Shows the appearance editor panel.
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

    /// Updates the ``lastShowTimestamp`` property.
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

    /// Returns the menu bar section with the given name.
    func section(withName name: MenuBarSection.Name) -> MenuBarSection? {
        sections.first { $0.name == name }
    }

    /// Returns the control item for the menu bar section with the given name.
    func controlItem(withName name: MenuBarSection.Name) -> ControlItem? {
        section(withName: name)?.controlItem
    }

    // MARK: - Per-Item Hotkeys

    /// Creates and reconciles the per-item hotkeys, then observes their changes.
    ///
    /// Called during setup, whenever the item cache changes, and after a
    /// profile is applied. Unlike the per-profile rebuild this is incremental:
    /// existing hotkey instances are preserved so a frequent cache tick does
    /// not tear down an in-use registration. A hotkey is created for every
    /// item currently in the menu bar plus every identifier that still has a
    /// saved binding (so a binding survives the owning app quitting), and is
    /// dropped only when its identifier is neither present nor configured.
    func rebuildItemHotkeys() {
        guard let appState else { return }

        let saved = Defaults.dictionary(forKey: .menuBarItemHotkeys) as? [String: Data] ?? [:]
        let dec = JSONDecoder()
        let enc = JSONEncoder()

        // Only real, identifiable items are assignable: skip Thaw's own control
        // items and items whose source app could not be resolved (their
        // identifier is an unstable UUID).
        let presentIdentifiers = Set(
            appState.itemManager.itemCache.managedItems
                .filter { !$0.isControlItem && $0.sourcePID != nil }
                .map(\.uniqueIdentifier)
        )
        let wantedIdentifiers = presentIdentifiers.union(saved.keys)

        var newHotkeys = itemHotkeys

        // Drop hotkeys for identifiers that are neither present nor configured.
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
                // Reconcile the live binding to the saved value (e.g. after a
                // profile apply). Only assign when it actually differs so we
                // avoid a redundant write back through the persistence sink.
                if existing.keyCombination != savedCombo {
                    existing.keyCombination = savedCombo
                }
                continue
            }

            let hotkey = Hotkey(action: .openMenuBarItem)
            hotkey.performSetup(with: appState)
            hotkey.keyCombination = savedCombo
            hotkeyItemMap[ObjectIdentifier(hotkey)] = identifier

            // Observe future changes from HotkeyRecorder and persist them.
            // Assigned after the initial keyCombination is set above, so —
            // like the previous dropFirst() Combine pipeline — the initial
            // value is never redundantly persisted.
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
    /// Resolves the live item from the current cache and routes it through the
    /// shared activation path. No-ops if the item is not currently present
    /// (e.g. its owning app has been quit).
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
        case desktopWallpaper
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
    /// This value is `true` if ``brightness`` is above ``Constants.menuBarBrightnessThreshold``.
    /// At the time of writing, if this value is `true`, the menu bar
    /// draws its items with a darker appearance.
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
