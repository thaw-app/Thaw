//
//  MenuBarManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI

/// Manager for the state of the menu bar.
@MainActor
final class MenuBarManager: ObservableObject {
    /// Information for the menu bar's average color on the active screen.
    @Published private(set) var averageColorInfo: MenuBarAverageColorInfo?

    /// Per-screen average colors for multi-monitor adaptive backgrounds.
    @Published private(set) var averageColors: [CGDirectDisplayID: MenuBarAverageColorInfo] = [:]

    /// A Boolean value that indicates whether the menu bar is either always hidden
    /// by the system, or automatically hidden and shown by the system based on the
    /// location of the mouse.
    @Published private(set) var isMenuBarHiddenBySystem = false

    /// A Boolean value that indicates whether the menu bar is hidden by the system
    /// according to a value stored in UserDefaults.
    @Published private(set) var isMenuBarHiddenBySystemUserDefaults = false

    /// A Boolean value that indicates whether the "ShowOnHover" feature is allowed.
    @Published var showOnHoverAllowed = true

    /// Timestamp of the last time a section was shown.
    private(set) var lastShowTimestamp: ContinuousClock.Instant?

    /// Reference to the settings window.
    @Published private var settingsWindow: NSWindow?

    /// Diagnostic logger for the menu bar manager.
    private let diagLog = DiagLog(category: "MenuBarManager")

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Per-item hotkeys, keyed by MenuBarItem.uniqueIdentifier. Each opens the
    /// item's menu when its key combination fires. Mirrors the per-profile
    /// hotkeys on ProfileManager.
    @Published private(set) var itemHotkeys: [String: Hotkey] = [:]

    /// Reverse map from a hotkey instance to the item identifier it opens.
    /// Read by Hotkey.Listener when an openMenuBarItem hotkey fires.
    var hotkeyItemMap: [ObjectIdentifier: String] = [:]

    /// Per-item hotkey persistence observers, keyed by item identifier so a
    /// single binding can be torn down without disturbing the others.
    private var itemHotkeyCancellables = [String: AnyCancellable]()

    /// Cancellable for the periodic average-color refresh, active only while settings is visible.
    private var averageColorRefreshCancellable: AnyCancellable?

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
        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            // Ignore the initial value during app startup. Treating the
            // current frontmost app as a "focus change" immediately on launch
            // triggers an expensive menu-open scan before the item manager
            // has even finished its first cache pass.
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if
                    let self,
                    let appState,
                    let hiddenSection = section(withName: .hidden),
                    let screen = appState.hidEventManager.bestScreen(appState: appState),
                    !appState.hidEventManager.isMouseInsideMenuBar(appState: appState, screen: screen),
                    !appState.hidEventManager.isMouseInsideIceBar(appState: appState),
                    appState.settings.general.autoRehide
                {
                    // Handle both focusedApp and smart strategies for focus changes
                    switch appState.settings.general.rehideStrategy {
                    case .focusedApp, .smart:
                        Task {
                            // Add delay for smart strategy to allow app focus to settle
                            let delay: TimeInterval = appState.settings.general.rehideStrategy == .smart ? 0.25 : 0.1
                            try await Task.sleep(for: .seconds(delay))

                            // Ignore rehide requests for a short grace period after showing.
                            if let lastShow = self.lastShowTimestamp,
                               lastShow.duration(to: .now) < .milliseconds(500)
                            {
                                self.diagLog.debug("Skipping rehide due to grace period")
                                return
                            }

                            // Check if any menu bar item has a menu open (for smart strategy)
                            if appState.settings.general.rehideStrategy == .smart,
                               await appState.itemManager.isAnyMenuBarItemMenuOpen()
                            {
                                return
                            }

                            hiddenSection.hide()
                        }
                    default:
                        break
                    }
                }
            }
            .store(in: &c)

        appState?.publisherForWindow(.settings)
            .sink { [weak self] window in
                self?.settingsWindow = window
            }
            .store(in: &c)

        if let appState {
            appState.settings.displaySettings.$configurations
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.updateControlItemStates()
                }
                .store(in: &c)

            // Refresh per-item hotkeys when the set of menu bar items changes,
            // so newly-arrived items become assignable. Debounced because the
            // item cache ticks frequently and rebuilding on every tick would
            // churn hotkey registrations.
            appState.itemManager.$itemCache
                .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.rebuildItemHotkeys()
                }
                .store(in: &c)
        }

        $settingsWindow
            .removeNil()
            .map { $0.publisher(for: \.isVisible) }
            .switchToLatest()
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
            .store(in: &c)

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
            appState.appearanceManager.$configuration
                .map { config in
                    let current = config.current
                    return current.backgroundKind == .adaptive || current.tintKind == .adaptive
                }
                .removeDuplicates()
                .sink { [weak self] isAdaptive in
                    guard let self else { return }
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
                .store(in: &c)
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

                // Use isHidden property - when section is shown, isHidden is false
                let isShowingHiddenSection = hiddenSection.map { !$0.isHidden } ?? false
                let isShowingAlwaysHiddenSection = alwaysHiddenSection.map { !$0.isHidden } ?? false

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
            targetScreens = NSScreen.managedScreens
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
                let allCaptured = NSScreen.managedScreens.allSatisfy {
                    self.averageColors.keys.contains($0.displayID)
                }
                if allCaptured { return }
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
            action: #selector(showMenuBarLayoutSettings),
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

    /// Shows the menu bar layout settings pane.
    @objc private func showMenuBarLayoutSettings() {
        guard let appState else {
            return
        }
        appState.navigationState.settingsNavigationIdentifier = .menuBarLayout
        appState.activate(withPolicy: .regular)
        appState.openWindow(.settings)
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
            itemHotkeyCancellables[identifier] = nil
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
            itemHotkeyCancellables[identifier] = hotkey.$keyCombination
                .dropFirst() // Skip the initial value we just set.
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak hotkey] newCombo in
                    guard let self, let hotkey else { return }
                    var dict = Defaults.dictionary(forKey: .menuBarItemHotkeys) as? [String: Data] ?? [:]
                    if let combo = newCombo, let data = try? enc.encode(combo) {
                        dict[identifier] = data
                    } else {
                        dict.removeValue(forKey: identifier)
                    }
                    Defaults.set(dict, forKey: .menuBarItemHotkeys)
                    self.hotkeyItemMap[ObjectIdentifier(hotkey)] = newCombo != nil ? identifier : nil
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
