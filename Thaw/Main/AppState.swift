//
//  AppState.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import CoreGraphics
import SwiftUI

/// The model for app-wide state.
@MainActor
final class AppState: ObservableObject {
    /// Information for the active space.
    @Published private(set) var activeSpace = SpaceInfo.activeSpace()

    /// A Boolean value that indicates whether the user is dragging a menu bar item.
    @Published private(set) var isDraggingMenuBarItem = false

    /// Tracks presentation of the update consent sheet.
    @Published var isUpdateConsentPresented = false

    /// Model for the app's settings.
    let settings = AppSettings()

    /// Model for the app's permissions.
    let permissions = AppPermissions()

    /// Model for app-wide navigation.
    let navigationState = AppNavigationState()

    /// Manager for the state of the menu bar.
    let menuBarManager = MenuBarManager()

    /// Manager for the menu bar's appearance.
    let appearanceManager = MenuBarAppearanceManager()

    /// Manager for menu bar item spacing.
    let spacingManager = MenuBarItemSpacingManager()

    /// Manager for menu bar items.
    let itemManager = MenuBarItemManager()

    /// Global cache for menu bar item images.
    let imageCache = MenuBarItemImageCache()

    /// Manager for input events received by the app.
    let hidEventManager = HIDEventManager()

    /// Manager for settings profiles.
    let profileManager = ProfileManager()

    /// Briefly adds a virtual display on single-display machines so the window
    /// server publishes the marker windows needed to resolve unidentified menu
    /// bar items, then tears it down.
    private(set) lazy var virtualDisplayProvoker = VirtualDisplayProvoker(appState: self)

    /// Manager for app updates.
    let updatesManager = UpdatesManager()

    /// Manager for user notifications.
    let userNotificationManager = UserNotificationManager()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Track open windows to prevent duplicates
    private var openWindows = Set<IceWindowIdentifier>()

    /// Track last known screen count to detect disconnects.
    private var lastKnownScreenCount = NSScreen.managedScreens.count

    /// Prevent repeated restart attempts.
    private var isRestarting = false

    /// Diagnostic logger for the app state.
    let diagLog = DiagLog(category: "AppState")

    private lazy var setupTask = Task { @MainActor in
        #if DEBUG
            // Debug builds always have diagnostic logging on so logs are
            // captured during development without depending on the toggle.
            DiagnosticLogger.shared.isEnabled = true
        #else
            if Defaults.bool(forKey: .enableDiagnosticLogging) {
                DiagnosticLogger.shared.isEnabled = true
            }
        #endif

        diagLog.debug("setupTask: starting AppState setup sequence")
        permissions.stopAllChecks()
        diagLog.debug("setupTask: permissions state = \(String(describing: self.permissions.permissionsState)), accessibility = \(self.permissions.accessibility.hasPermission), screenRecording = \(self.permissions.screenRecording.hasPermission)")

        settings.performSetup(with: self)
        menuBarManager.performSetup(with: self)
        diagLog.debug("setupTask: settings and menuBarManager setup complete")

        diagLog.debug("setupTask: starting MenuBarItemService XPC connection")
        await MenuBarItemService.Connection.shared.start()
        diagLog.debug("setupTask: MenuBarItemService XPC connection started")

        appearanceManager.performSetup(with: self)
        hidEventManager.performSetup(with: self)
        diagLog.debug("setupTask: starting itemManager setup")
        await itemManager.performSetup(with: self)
        diagLog.debug("setupTask: itemManager setup scheduled, invalidating menuBarHeightCache")
        NSScreen.invalidateMenuBarHeightCache()
        diagLog.debug("setupTask: starting imageCache setup")
        imageCache.performSetup(with: self)
        diagLog.debug("setupTask: imageCache setup complete")
        updatesManager.performSetup(with: self)
        userNotificationManager.performSetup(with: self)
        profileManager.performSetup(with: self)

        configureCancellables()
        diagLog.debug("setupTask: AppState setup sequence complete")
    }

    /// Allows explicit starting of the updater from UI flows.
    func startUpdaterIfNeeded() {
        updatesManager.startUpdaterIfNeeded()
    }

    func dismissWindow(_ id: IceWindowIdentifier) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.openWindows.remove(id)
            self.diagLog.debug("Dismissing window with id: \(id)")
            EnvironmentValues().dismissWindow(id: id)
        }
    }

    /// Performs app state setup.
    ///
    /// - Parameter hasPermissions: If `true`, continues with setup normally.
    ///   If `false`, prompts the user to grant permissions.
    func performSetup(hasPermissions: Bool) {
        if hasPermissions {
            Task {
                diagLog.debug("Setting up app state")
                await setupTask.value

                // Warm up the activation policy system.
                NSApp.setActivationPolicy(.regular)
                try? await Task.sleep(for: .milliseconds(50))
                NSApp.setActivationPolicy(.accessory)

                diagLog.debug("Finished setting up app state")
            }
        } else {
            Task {
                // Delay to prevent conflicts with the app delegate.
                try? await Task.sleep(for: .milliseconds(100))
                activate(withPolicy: .regular)
                dismissWindow(.settings) // Shouldn't be open anyway.
                openWindow(.permissions)
            }
        }
    }

    /// Configures the internal observers for the app state.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // Listen for changes to the active space. We need handle some special
        // cases that NSWorkspace.shared.notificationCenter seems to miss.
        //
        // Special cases:
        //
        // * Changes to the frontmost application -- may indicate that a space
        //   on another display was made active.
        // * Left mouse down -- user may have clicked into a fullscreen space.
        //   To account for variations in system timing, we publish a value
        //   immediately upon receipt of the event, then publish another value
        //   after a delay.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .discardMerge(NSWorkspace.shared.publisher(for: \.frontmostApplication))
            .discardMerge(
                EventMonitor.publish(events: .leftMouseDown, scope: .universal)
                    .throttle(for: .seconds(0.15), scheduler: DispatchQueue.main, latest: true)
                    .flatMap { _ in
                        let initial = Just(())
                        let delayed = initial.delay(for: 0.1, scheduler: DispatchQueue.main)
                        return Publishers.Merge(initial, delayed)
                    }
            )
            .replace { Bridging.getActiveSpaceID() }
            .removeDuplicates()
            .sink { [weak self] spaceID in
                self?.activeSpace = SpaceInfo(spaceID: spaceID)
            }
            .store(in: &c)

        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .receive(on: DispatchQueue.main)
            .map { $0 == .current }
            .removeDuplicates()
            .sink { [weak self] isFrontmost in
                self?.navigationState.isAppFrontmost = isFrontmost
            }
            .store(in: &c)

        publisherForWindow(.settings)
            .removeNil()
            .map { $0.publisher(for: \.isVisible) }
            .switchToLatest()
            .replaceEmpty(with: false)
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .removeDuplicates()
            .sink { [weak self] isPresented in
                guard let self else { return }
                self.navigationState.isSettingsPresented = isPresented

                // Update openWindows tracking based on actual window visibility
                if isPresented {
                    self.openWindows.insert(.settings)
                    // Start Sparkle consent flow the first time settings is shown.
                    if !Defaults.bool(forKey: .hasSeenUpdateConsent) {
                        self.isUpdateConsentPresented = true
                    } else {
                        self.updatesManager.startUpdaterIfNeeded()
                    }
                } else {
                    self.openWindows.remove(.settings)
                    self.deactivate(withPolicy: .accessory)
                }
            }
            .store(in: &c)

        hidEventManager.$isDraggingMenuBarItem
            .removeDuplicates()
            .sink { [weak self] isDragging in
                self?.isDraggingMenuBarItem = isDragging
            }
            .store(in: &c)

        Publishers.CombineLatest(
            navigationState.$isAppFrontmost,
            navigationState.$isSettingsPresented
        )
        .map { $0 && $1 }
        .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
        .merge(with: Just(true).delay(for: 1, scheduler: DispatchQueue.main))
        .sink { [weak self] shouldUpdate in
            guard let self, shouldUpdate else {
                return
            }
            Task {
                await self.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
                // Log cache status periodically (only if cache is getting full)
                if self.imageCache.cacheSize > 15 {
                    self.imageCache.logCacheStatus("Periodic update")
                }
            }
        }
        .store(in: &c)

        menuBarManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        permissions.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        settings.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        updatesManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)

        // After each cache cycle settles, let the provoker decide whether to
        // briefly add a virtual display to resolve any single-display orphans.
        itemManager.$itemCache
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.virtualDisplayProvoker.considerProvoking()
            }
            .store(in: &c)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .map { _ in NSScreen.managedScreens.count }
            .sink { [weak self] count in
                guard let self else { return }
                defer { self.lastKnownScreenCount = count }
                if count < self.lastKnownScreenCount {
                    self.diagLog.info("Display disconnected: refresh item cache + cleanup image cache")
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        // A display change relocates items to the remaining
                        // display and leaves the menu bar geometry (Control
                        // Center position, item bounds) unsettled for a short
                        // window. Open a settling period so saved-layout restores
                        // defer until the bar restabilizes and then run once on
                        // settled geometry. Without this, a restore could fire
                        // against transient off-screen geometry: Control Center's
                        // stale left edge produces a negative notch-overflow
                        // budget that collapses the hidden section into visible
                        // and is then persisted into the saved order.
                        self.itemManager.startSettlingPeriod(reason: "displayDisconnect")
                        // Force item cache rebuild so displayID reflects current
                        // display geometry (items moved to remaining display).
                        await self.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
                        // Force image cache: remove entries for items no longer
                        // present, trigger re-capture for current display.
                        self.imageCache.performCacheCleanup()
                        await self.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
                        self.diagLog.info("Cache refresh complete after display disconnect")
                    }
                } else if count > self.lastKnownScreenCount {
                    self.diagLog.info("Display connected: refresh item cache")
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        // Defer the saved-layout restore until the menu bar
                        // geometry settles after the new display attaches; see
                        // the disconnect branch above for the rationale.
                        self.itemManager.startSettlingPeriod(reason: "displayConnect")
                        // Items keep their windowIDs when moving to new display.
                        // Item cache rebuild picks up new items on the added display.
                        await self.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
                        self.diagLog.info("Item cache refreshed after display connect")
                    }
                }
            }
            .store(in: &c)

        cancellables = c
    }

    /// Relaunches the current app instance silently.
    func restartSelf() {
        guard !isRestarting else { return }
        isRestarting = true

        // Save image cache to disk before restarting so new instance can load it
        imageCache.saveToDisk()

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        config.createsNewApplicationInstance = true
        config.promptsUserIfNeeded = false

        Task { @MainActor in
            do {
                _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config)
                try? await Task.sleep(for: .milliseconds(500))
                exit(0)
            } catch {
                diagLog.error("Failed to relaunch app: \(error.localizedDescription)")
                isRestarting = false
            }
        }
    }

    /// Returns a Boolean value indicating whether the app has been
    /// granted the permission associated with the given key.
    func hasPermission(_ key: AppPermissions.PermissionKey) -> Bool {
        switch key {
        case .accessibility:
            permissions.accessibility.hasPermission
        case .screenRecording:
            permissions.screenRecording.hasPermission
        }
    }

    /// Returns a publisher for the window with the given identifier.
    func publisherForWindow(_ id: IceWindowIdentifier) -> some Publisher<NSWindow?, Never> {
        NSApp.publisher(for: \.windows)
            .map { windows in
                windows.first { $0.identifier?.rawValue == id.rawValue }
            }
    }

    func openWindow(_ id: IceWindowIdentifier) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            if self.openWindows.contains(id) {
                self.diagLog.debug("Window \(id) already open, activating existing window")
                self.activate(withPolicy: .regular)
                return
            }

            self.openWindows.insert(id)
            self.diagLog.debug("Opening window with id: \(id)")
            EnvironmentValues().openWindow(id: id)

            try? await Task.sleep(for: .milliseconds(100))
            self.activate(withPolicy: .regular)
        }
    }

    func activate(withPolicy policy: NSApplication.ActivationPolicy? = nil) {
        if let policy {
            NSApp.setActivationPolicy(policy)
        }

        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard let frontmost = NSWorkspace.shared.frontmostApplication else {
                NSRunningApplication.current.activate()
                return
            }
            NSRunningApplication.current.activate(from: frontmost)
        }
    }

    /// Deactivates the app and sets its activation policy.
    func deactivate(withPolicy policy: NSApplication.ActivationPolicy? = nil) {
        if let policy {
            NSApp.setActivationPolicy(policy)
        }
        NSApp.deactivate()
    }
}
