//
//  AppState.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AsyncAlgorithms
import Combine
import CoreGraphics
import Observation
import SwiftUI

/// The model for app-wide state.
@MainActor
@Observable
final class AppState {
    /// Information for the active space.
    private(set) var activeSpace = SpaceInfo.activeSpace()

    /// A Boolean value that indicates whether the user is dragging a menu bar item.
    private(set) var isDraggingMenuBarItem = false

    /// Tracks presentation of the update consent sheet.
    var isUpdateConsentPresented = false

    /// Tracks presentation of the onboarding sheet.
    var isOnboardingPresented = false

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

    /// Owner of the user's menu bar spacer items.
    let spacerManager = MenuBarSpacerManager()

    /// Owner of user-authored menu bar item groups.
    let itemGroupManager = MenuBarItemGroupManager()

    /// Manager for input events received by the app.
    let hidEventManager = HIDEventManager()

    /// Manager for settings profiles.
    let profileManager = ProfileManager()

    /// Manager for app updates.
    let updatesManager = UpdatesManager()

    /// Manager for user notifications.
    let userNotificationManager = UserNotificationManager()

    /// Engages zen mode while the screen is mirrored or being shared.
    let presentationMonitor = PresentationMonitor()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Observes `navigationState.isAppFrontmost` and `isSettingsPresented`.
    private var navigationStateObservationTask: Task<Void, Never>?

    /// Observes `hidEventManager.isDraggingMenuBarItem`.
    private var hidEventManagerObservationTask: Task<Void, Never>?

    /// Observes `NSApplication.didChangeScreenParametersNotification`, debounced.
    private var screenParametersObservationTask: Task<Void, Never>?

    /// Track open windows to prevent duplicates
    private var openWindows = Set<IceWindowIdentifier>()

    /// Whether settings, permissions, search, or the Thaw Bar is up.
    /// Those surfaces activate as a regular app, so a menu-bar hide retry
    /// must not switch back to accessory and hide their Dock icon.
    var explicitUIWantsRegularActivation: Bool {
        navigationState.isSettingsPresented
            || navigationState.isSearchPresented
            || navigationState.isIceBarPresented
            || openWindows.contains(.settings)
            || openWindows.contains(.permissions)
    }

    /// Track last known screen count to detect disconnects.
    private var lastKnownScreenCount = NSScreen.screens.count

    /// Prevent repeated restart attempts.
    private var isRestarting = false

    /// Diagnostic logger for the app state.
    let diagLog = DiagLog(category: "AppState")

    /// `@ObservationIgnored`: the macro can't handle a `lazy` property, and no
    /// view reads it.
    @ObservationIgnored
    private lazy var setupTask = Task { @MainActor in
        // Repoint the XPC service on rotation. Installed before logging starts
        // so the first rotation is covered too.
        DiagnosticLogger.shared.onRotate = {
            Task { await MenuBarItemService.Connection.shared.syncLogging() }
        }

        // Opening a log file prunes, so set retention first; the settings model
        // isn't built yet.
        DiagnosticLogger.shared.setRotationPolicy(AdvancedSettings.persistedRotationPolicy())

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
        // Capture is optional: don't block item/manager setup if the helper is slow.
        Task {
            await MenuBarCaptureService.Connection.shared.start()
        }
        diagLog.debug("setupTask: MenuBarCaptureService XPC start kicked off")

        appearanceManager.performSetup(with: self)
        hidEventManager.performSetup(with: self)
        diagLog.debug("setupTask: starting itemManager setup")
        await itemManager.performSetup(with: self)
        diagLog.debug("setupTask: itemManager setup scheduled, invalidating menuBarHeightCache")
        NSScreen.invalidateMenuBarHeightCache()
        diagLog.debug("setupTask: starting imageCache setup")
        imageCache.performSetup(with: self)
        diagLog.debug("setupTask: imageCache setup complete")
        spacerManager.performSetup(with: self)
        presentationMonitor.performSetup(with: self)
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

    /// Presents the onboarding sheet if the user hasn't seen it yet.
    func presentOnboardingIfNeeded() {
        if !Defaults.bool(forKey: .hasSeenOnboarding) {
            isOnboardingPresented = true
        }
    }

    /// Completes first-launch setup based on the permissions currently granted,
    /// then brings the app to regular activation and opens Settings. Shared by
    /// the permissions window's Continue button and onboarding's final slide.
    func completeFirstLaunchSetup() {
        dismissWindow(.permissions)
        Defaults.set(true, forKey: .hasSeenOnboarding)

        let hasPermissions = permissions.permissionsState != .missing
        performSetup(hasPermissions: hasPermissions)
        Defaults.set(true, forKey: .hasCompletedFirstLaunch)

        guard hasPermissions else { return }

        Task {
            activate(withPolicy: .regular)
            openWindow(.settings)
        }
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
                        self.presentOnboardingIfNeeded()
                    }
                } else {
                    self.openWindows.remove(.settings)
                    self.deactivate(withPolicy: .accessory)
                }
            }
            .store(in: &c)

        hidEventManagerObservationTask = Task { [weak self, weak hidEventManager] in
            let changes = Observations { hidEventManager?.isDraggingMenuBarItem ?? false }
            for await isDragging in changes {
                guard let self else { return }
                guard self.isDraggingMenuBarItem != isDragging else { continue }
                self.isDraggingMenuBarItem = isDragging
            }
        }

        // No throttle: these flags only flip on user navigation.
        navigationStateObservationTask = Task { [weak self] in
            guard let self else { return }
            let changes = Observations { [navigationState] in
                (navigationState.isAppFrontmost, navigationState.isSettingsPresented)
            }
            for await (isAppFrontmost, isSettingsPresented) in changes {
                guard isAppFrontmost, isSettingsPresented else { continue }
                await self.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
                // Log cache status periodically (only if cache is getting full)
                if self.imageCache.cacheSize > 15 {
                    self.imageCache.logCacheStatus("Periodic update")
                }
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            await self.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
            if self.imageCache.cacheSize > 15 {
                self.imageCache.logCacheStatus("Periodic update")
            }
        }

        // Child models are `@Observable`, so views need no change forwarding.

        // Notification isn't Sendable, so the stream carries Void and the
        // screen count is re-read per event.
        let (screenParameterEvents, screenParameterContinuation) = AsyncStream<Void>.makeStream()
        screenParametersObservationTask = Task { @MainActor [weak self] in
            let observer = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in screenParameterContinuation.yield(()) }
            defer { NotificationCenter.default.removeObserver(observer) }
            for await _ in screenParameterEvents.debounce(for: .seconds(0.5)) {
                guard let self else { return }
                let count = NSScreen.screens.count
                defer { self.lastKnownScreenCount = count }
                if count < self.lastKnownScreenCount {
                    self.diagLog.info("Display disconnected: refresh item cache + cleanup image cache")
                    // Menu bar geometry is unsettled right after a display change.
                    // Defer layout restores: Control Center's stale left edge gives
                    // a negative notch-overflow budget that collapses hidden into
                    // visible and gets persisted.
                    self.itemManager.startSettlingPeriod(reason: "displayDisconnect")
                    // Force item cache rebuild so displayID reflects current
                    // display geometry (items moved to remaining display).
                    await self.itemManager.cacheItemsRegardless(options: .init(skipRecentMoveCheck: true))
                    // Force image cache: remove entries for items no longer
                    // present, trigger re-capture for current display.
                    self.imageCache.performCacheCleanup()
                    await self.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
                    self.diagLog.info("Cache refresh complete after display disconnect")
                } else if count > self.lastKnownScreenCount {
                    self.diagLog.info("Display connected: refresh item cache")
                    // Defer the saved-layout restore until the menu bar
                    // geometry settles after the new display attaches; see
                    // the disconnect branch above for the rationale.
                    self.itemManager.startSettlingPeriod(reason: "displayConnect")
                    // Items keep their windowIDs when moving to new display.
                    // Item cache rebuild picks up new items on the added display.
                    await self.itemManager.cacheItemsRegardless(options: .init(skipRecentMoveCheck: true))
                    self.diagLog.info("Item cache refreshed after display connect")
                }
            }
        }

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
        if policy == .regular {
            menuBarManager.invalidatePendingAccessoryActivation()
        }
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
