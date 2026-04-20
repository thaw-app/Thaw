//
//  AppState.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import CoreGraphics
import Darwin.Mach
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

    /// Manager for app updates.
    let updatesManager = UpdatesManager()

    /// Manager for user notifications.
    let userNotificationManager = UserNotificationManager()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Track open windows to prevent duplicates
    private var openWindows = Set<IceWindowIdentifier>()

    /// The background task for periodic memory monitoring.
    private var memoryMonitoringTask: Task<Void, Never>?

    /// Track last known screen count to detect disconnects.
    private var lastKnownScreenCount = NSScreen.screens.count

    /// Prevent repeated restart attempts.
    private var isRestarting = false

    /// Diagnostic logger for the app state.
    let diagLog = DiagLog(category: "AppState")

    /// Async setup actions, run once on first access.
    private lazy var setupTask = Task {
        // Enable diagnostic logging early if the user had it enabled
        if Defaults.bool(forKey: .enableDiagnosticLogging) {
            DiagnosticLogger.shared.isEnabled = true
        }

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
        diagLog.debug("setupTask: itemManager setup complete, invalidating menuBarHeightCache")
        NSScreen.invalidateMenuBarHeightCache()
        diagLog.debug("setupTask: starting imageCache setup")
        imageCache.performSetup(with: self)
        diagLog.debug("setupTask: imageCache setup complete")
        updatesManager.performSetup(with: self)
        userNotificationManager.performSetup(with: self)
        profileManager.performSetup(with: self)

        configureCancellables()

        // Start memory monitoring
        startMemoryMonitoring()
        diagLog.debug("setupTask: AppState setup sequence complete")
    }

    /// Allows explicit starting of the updater from UI flows.
    func startUpdaterIfNeeded() {
        updatesManager.startUpdaterIfNeeded()
    }

    /// Starts periodic memory monitoring to track all memory usage.
    private func startMemoryMonitoring() {
        memoryMonitoringTask?.cancel()
        memoryMonitoringTask = Task {
            let formatter = ISO8601DateFormatter()
            do {
                while true {
                    let memoryUsage = getMemoryInfo()
                    let timestamp = formatter.string(from: Date())

                    // Always log memory usage, not just high usage
                    diagLog.info("Memory usage at \(timestamp): \(memoryUsage / 1024 / 1024)MB")

                    // Log warnings for specific conditions
                    let memoryWarningThreshold: Int64 = 500 * 1024 * 1024 // 500MB
                    if memoryUsage > memoryWarningThreshold {
                        diagLog.warning("High memory usage detected: \(memoryUsage / 1024 / 1024)MB")
                    }

                    // Log component sizes for debugging — no MainActor.run needed
                    // as AppState is already @MainActor isolated.
                    let imageCount = imageCache.images.count
                    let windowCount = openWindows.count

                    if imageCount > 20 {
                        diagLog.warning("Large image cache: \(imageCount) items")
                    }
                    if windowCount > 5 {
                        diagLog.warning("Many open windows: \(windowCount)")
                    }

                    try await Task.sleep(for: .seconds(300))
                }
            } catch {
                // CancellationError — task was cancelled, exit cleanly.
            }
        }
    }

    /// Dismisses the window with the given identifier.
    func dismissWindow(_ id: IceWindowIdentifier) {
        // Async prevents conflicts with SwiftUI.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.openWindows.remove(id)
            self.diagLog.debug("Dismissing window with id: \(id)")
            EnvironmentValues().dismissWindow(id: id)
        }
    }

    /// Gets the memory footprint of the task.
    private func getMemoryInfo() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / UInt32(MemoryLayout<integer_t>.size)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else {
            return 0
        }
        return Int64(info.phys_footprint)
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

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .map { _ in NSScreen.screens.count }
            .sink { [weak self] count in
                guard let self else { return }
                defer { self.lastKnownScreenCount = count }
                if count < self.lastKnownScreenCount {
                    self.diagLog.info("Detected display disconnect; state will be refreshed automatically")
                    // App restart disabled - memory leak fixes allow dynamic display handling
                    // self.restartSelf()
                } else if count > self.lastKnownScreenCount {
                    self.diagLog.info("Detected display connect; state will be refreshed automatically")
                    // App restart disabled - memory leak fixes allow dynamic display handling
                    // self.restartSelf()
                }
            }
            .store(in: &c)

        cancellables = c
    }

    /// Relaunches the current app instance silently.
    private func restartSelf() {
        guard !isRestarting else { return }
        isRestarting = true

        Task { @MainActor [diagLog] in
            // Save image cache to disk before restarting so new instance can load it
            imageCache.saveToDisk()

            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.addsToRecentItems = false
            config.createsNewApplicationInstance = true
            config.promptsUserIfNeeded = false

            if let url = Bundle.main.bundleURL as URL? {
                do {
                    _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
                    try? await Task.sleep(for: .milliseconds(300))
                    NSApp.terminate(nil)
                } catch {
                    diagLog.error("Failed to relaunch app: \(error.localizedDescription)")
                    isRestarting = false
                }
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

    /// Opens the window with the given identifier.
    func openWindow(_ id: IceWindowIdentifier) {
        // Async prevents conflicts with SwiftUI.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Check if window is already open to prevent recreation
            if self.openWindows.contains(id) {
                self.diagLog.debug("Window \(id) already open, activating existing window")
                // If window already exists, just activate it
                self.activate(withPolicy: .regular)
                return
            }

            self.openWindows.insert(id)
            self.diagLog.debug("Opening window with id: \(id)")
            EnvironmentValues().openWindow(id: id)

            // Ensure activation after window opens
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.activate(withPolicy: .regular)
            }
        }
    }

    /// Activates the app and sets its activation policy.
    func activate(withPolicy policy: NSApplication.ActivationPolicy? = nil) {
        if let policy {
            NSApp.setActivationPolicy(policy)
        }

        // Force activation and bring to front
        NSApp.activate(ignoringOtherApps: true)

        // Also try through NSRunningApplication as fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
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
