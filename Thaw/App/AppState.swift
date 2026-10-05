//
//  AppState.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import AsyncAlgorithms
import Combine
import MenuBarModel
import Observation
import PlatformRuntimeKit
import SwiftUI
import ThawCapture

/// AppDelegate creates the single environment object owning long-lived subsystems; allocation is safe before permissions are granted.
/// Subsystems start at most once through bootstrapTask, whose setup order follows dependencies.
@MainActor
@Observable
final class AppState {
    // MARK: - Owned subsystems

    // Core models. Independent of the menu bar stack and of one another.

    /// The user's preferences, backed by UserDefaults. Almost everything
    /// downstream reads it, which is why it is brought up first.
    let settings = AppSettings()

    /// Polls permissions from creation until bootstrap; post-launch revocation takes effect on the next run.
    let permissions = AppPermissions()

    /// Observers publish cross-window navigation and visibility here for the settings UI.
    let navigationState = AppNavigationState()

    /// Named snapshots of the user's settings on disk. Touches only files, so
    /// it neither needs nor supplies anything the menu bar stack depends on.
    let profileManager = ProfileManager()

    // Menu bar stack. Set up in dependency order; see bootstrapTask.

    /// The sections, their control items, and the show/hide state machine.
    let menuBarManager = MenuBarManager()

    /// Paints tint, border, shadow and shape over the system menu bar.
    let appearanceManager = MenuBarAppearanceManager()

    /// Changes system spacing and relaunches affected apps only on user slider input, never during bootstrap.
    let spacingManager = MenuBarItemSpacingManager()

    /// The item inventory, what sits in the menu bar, where, and the moves
    /// that put it there. Everything below queries it.
    let itemManager = MenuBarItemManager()

    /// Rendered pictures of the items, shared by the layout editor and the
    /// Thaw bar. Fed from itemManager, so it is set up after it.
    let imageCache = MenuBarItemImageCache()

    /// Reveals concealed items temporarily when their icon changes.
    let alertRevealWatcher = MenuBarItemAlertRevealWatcher()
    let presentationMonitor = PresentationMonitor()
    let appRunningTriggers = AppRunningTriggersManager()

    /// Owner of the user's menu bar spacer items.
    let spacerManager = MenuBarSpacerManager()
    let thawBarOnlyProxies = ThawBarOnlyProxies()
    let itemStandInSlots = ItemStandInSlots()
    let screenCorners = ScreenCorners()
    let itemHints = ItemHints()
    let groupFolders = GroupFolders()

    /// Owner of user-authored menu bar item groups.
    let itemGroupManager = MenuBarItemGroupManager()

    /// Transient, user-facing explanations for refused layout actions.
    let layoutFeedback = LayoutBarFeedbackCenter()

    // System services.

    /// Keyboard and pointer taps: hotkeys, plus the drag tracking mirrored
    /// into isDraggingMenuBarItem.
    let hidEventManager = HIDEventManager()

    /// Sparkle wrapper. Stays idle until the user consents, so setting it up
    /// does not by itself reach the network.
    let updatesManager = UpdatesManager()

    /// Delivers the app's user notifications and owns their categories and
    /// actions.
    let userNotificationManager = UserNotificationManager()

    /// Receives Control Center commands through Darwin notifications; see ControlCommandObserver for why commands avoid App Groups.
    let controlCommandObserver = ControlCommandObserver()

    /// Publishes Control Center state through the shared App Group; commands return through Darwin notifications.
    let controlStatePublisher = ControlStatePublisher()

    /// The floating Swap bar: swap the shown and hidden groups, switch
    /// profiles, and reach the section and zen toggles without the menu.
    let swapBarManager = SwapBarManager()

    /// The panel Thaw's own icon raises in place of its status menu, a Lab
    /// experiment. Nothing is constructed until the first press with it on.
    let controlItemPanel = ControlItemPanelController()

    /// Lab recording watcher reads only public CoreAudio and CoreMediaIO state, independent of other subsystems.
    let recordingWatchManager = RecordingWatchManager()

    let applicationMenuCover = ApplicationMenuCover()

    /// Diagnostic logger for the app state.
    let diagLog = DiagLog(category: "AppState")

    // MARK: - Published state

    /// observeActiveSpace() compensates for under-reported system space changes.
    private(set) var activeSpace = SpaceInfo.activeSpace()

    /// Mirror of the event layer's drag flag, so views can watch a drag
    /// without subscribing to HIDEventManager themselves.
    private(set) var isDraggingMenuBarItem = false

    /// Consent sheet is only for users who completed onboarding without answering the update question.
    var isUpdateConsentPresented = false

    /// Consumed by the permissions window to replay the tour once, regardless of stored flags.
    var replayRequested = false

    /// The version an available update installs, while its notes are open in
    /// What's New. Sparkle's own release notes are off, so this is where the
    /// update's notes are read before installing.
    var pendingUpdateVersion: String?

    // MARK: - Window bookkeeping

    /// Track open windows to prevent duplicates
    private var openWindows = Set<ThawWindowIdentifier>()

    /// Live windows keyed by scene identifier.
    /// - Note: onWindowChange supplies these because unreliable NSApp.windows KVO would leave openWindows stuck after closing.
    private var trackedWindows = [ThawWindowIdentifier: NSWindow]()

    /// Per-window visibility observers, keyed by identifier.
    private var windowVisibilityCancellables = [ThawWindowIdentifier: AnyCancellable]()

    /// Fresh EnvironmentValues have inert window actions; scenes register live actions without eagerly creating windows.
    private var openWindowAction: OpenWindowAction?
    private var dismissWindowAction: DismissWindowAction?
    private var pendingOpenWindows = Set<ThawWindowIdentifier>()

    // MARK: - Private state

    /// Holds the subscriptions made by installObservers(). Emptied before
    /// they are remade, so the observers can never end up doubled.
    private var cancellables = Set<AnyCancellable>()

    /// Watches navigationState's observable focus and Settings visibility.
    private var navigationStateObservationTask: Task<Void, Never>?

    /// Track last known screen count to detect disconnects.
    private var lastKnownScreenCount = NSScreen.managedScreens.count

    /// Prevent repeated restart attempts.
    private var isRestarting = false

    // MARK: - Bootstrap

    /// Callers await the same lazy task so bootstrap runs once.
    /// Keep dependency order: each setup assumes preceding subsystems are live.
    @ObservationIgnored
    private lazy var bootstrapTask = Task { @MainActor [self] in
        #if DEBUG
            // Debug builds always have diagnostic logging on so logs are
            // captured during development without depending on the toggle.
            DiagnosticLogger.shared.isEnabled = true
        #else
            if Defaults.bool(forKey: .enableDiagnosticLogging) {
                DiagnosticLogger.shared.isEnabled = true
            }
        #endif

        diagLog.debug("bootstrap: starting AppState setup sequence")

        // Choose helper capture routing once, before any subsystem captures a frame.
        ScreenCapture.routesThroughCaptureService = Defaults.bool(forKey: .captureViaXPCService)
        permissions.stopAllChecks()
        diagLog.debug("bootstrap: permissions state = \(String(describing: self.permissions.permissionsState)), accessibility = \(self.permissions.accessibility.hasPermission), screenRecording = \(self.permissions.screenRecording.hasPermission)")

        settings.performSetup(with: self)
        menuBarManager.performSetup(with: self)
        // A refused preferences watcher stays stopped; recreate it after either a table-file grant or Full Disk Access.
        permissions.onPermissionTransition = { [weak self] permission, granted in
            guard let self, granted, permission === permissions.fullDiskAccess else { return }
            (menuBarManager.sectionController as? RuntimeSectionController)?.restartPreferencesWatcher()
        }
        diagLog.debug("bootstrap: settings and menuBarManager setup complete")

        appearanceManager.performSetup(with: self)
        hidEventManager.performSetup(with: self)
        diagLog.debug("bootstrap: starting itemManager setup")
        await itemManager.performSetup(with: self)
        diagLog.debug("bootstrap: itemManager setup scheduled, invalidating menuBarHeightCache")
        NSScreen.invalidateMenuBarHeightCache()
        diagLog.debug("bootstrap: starting imageCache setup")
        imageCache.activate(with: self)
        alertRevealWatcher.performSetup(with: self)
        appRunningTriggers.start(
            reveal: { [weak self] in self?.menuBarManager.sectionController.revealItemTemporarily($0) },
            release: { [weak self] in self?.menuBarManager.sectionController.concealTemporarilyRevealedItem($0) }
        )
        presentationMonitor.performSetup(with: self)
        spacerManager.performSetup(with: self)
        itemStandInSlots.performSetup(with: self)
        screenCorners.performSetup(with: self)
        itemHints.performSetup(with: self)
        groupFolders.performSetup(with: self)
        thawBarOnlyProxies.performSetup(with: self)
        diagLog.debug("bootstrap: imageCache setup complete")
        updatesManager.performSetup(with: self)
        userNotificationManager.performSetup(with: self)
        profileManager.performSetup(with: self)
        controlCommandObserver.performSetup(with: self)
        controlStatePublisher.performSetup(with: self)
        swapBarManager.performSetup(with: self)
        controlItemPanel.performSetup(with: self)
        recordingWatchManager.performSetup(with: self)
        applicationMenuCover.performSetup(with: self)
        // The widget preview item exists only inside a running process, so
        // every launch re-publishes it when the user last left it enabled.
        StatusIconWidgetController.shared.restore()

        installObservers()
        MemoryReclaimer.start()
        diagLog.debug("bootstrap: AppState setup sequence complete")
    }

    /// Called by AppDelegate and again after first-launch permission setup.
    /// - Parameter granted: True runs bootstrap with required grants; false keeps subsystems inert and opens permissions.
    func launch(withPermissions granted: Bool) {
        guard granted else {
            Task {
                // The delegate is still inside its launch callback here;
                // changing the activation policy out from under it races.
                try? await Task.sleep(for: .milliseconds(100))
                activate(withPolicy: .regular)
                dismissWindow(.settings)
                openWindow(.permissions)
            }
            return
        }

        // Before bootstrap, so the first cache pass already recovers through
        // the app's store wrapper and capture.
        PositionStoreItemSource.environment = .thaw

        Task {
            diagLog.debug("Setting up app state")
            await bootstrapTask.value

            // Warm up the activation policy system.
            applyActivationPolicy(.regular)
            try? await Task.sleep(for: .milliseconds(50))
            applyActivationPolicy(.accessory)

            diagLog.debug("Finished setting up app state")
        }
    }

    /// Completes first-launch setup based on the permissions currently granted,
    /// then brings the app to regular activation and opens Settings.
    func completeFirstLaunchSetup() {
        dismissWindow(.permissions)

        let hasPermissions = permissions.permissionsState != .missing
        launch(withPermissions: hasPermissions)
        Defaults.set(true, forKey: .hasCompletedFirstLaunch)

        guard hasPermissions else { return }

        Task {
            activate(withPolicy: .regular)
            openWindow(.settings)
        }
    }

    /// Select the destination pane before opening Settings so construction reads it without losing the sidebar's first render.
    func completeOnboarding(outcome: OnboardingOutcome, opening pane: SettingsNavigationIdentifier?) {
        settings.general.simpleMode = outcome.simpleMode

        if let pane {
            SettingsSearchNavigation.selectSidebarPane(pane, navigationState: navigationState)
        }

        if Constants.supportsSparkleUpdates {
            Defaults.set(true, forKey: .hasSeenUpdateConsent)
            updatesManager.automaticallyChecksForUpdates = outcome.automaticUpdates
            updatesManager.automaticallyDownloadsUpdates = outcome.automaticUpdates
            startUpdaterIfNeeded()
        }

        Defaults.set(true, forKey: .hasSeenOnboarding)
        Defaults.set(Constants.currentOnboardingVersion, forKey: .onboardingVersion)
        permissions.refreshPermissionsState()
        completeFirstLaunchSetup()
    }

    /// Overrides stored "seen" state to replay onboarding; opening the permissions window brings Thaw forward.
    func replayOnboarding() {
        replayRequested = true
        openWindow(.permissions)
    }

    /// First launches and upgrades without changelog content record the version silently, leaving onboarding to handle new users.
    /// Record synchronously before the async repository fetch to avoid repeated prompts after failures.
    func presentWhatsNewForUpgradeIfNeeded() {
        let current = Constants.versionString
        guard let lastSeen = Defaults.string(forKey: .lastWhatsNewVersion) else {
            Defaults.set(current, forKey: .lastWhatsNewVersion)
            return
        }
        guard lastSeen != current else { return }
        Defaults.set(current, forKey: .lastWhatsNewVersion)

        Task {
            let allowFetch = settings.advanced.fetchReleaseNotes
            guard await ChangelogDocument.load(allowFetch: allowFetch).document?.newestRelease != nil else { return }
            activate(withPolicy: .regular)
            openWindow(.whatsNew)
        }
    }

    /// Allows explicit starting of the updater from UI flows.
    func startUpdaterIfNeeded() {
        updatesManager.startUpdaterIfNeeded()
    }

    /// exit(0) bypasses termination teardown; run it here to prevent macOS 27 ghost icons with dead menus after relaunch.
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
                // Restore blocked items before exit so none remain off-screen; this is a no-op on macOS 27.
                _ = await itemManager.restoreBlockedItemsToVisible()
                menuBarManager.tearDownControlItemsForTermination()
                diagLog.info("Restart: tore down control items, waiting for MenuBarAgent to reclaim")
                try? await Task.sleep(for: .milliseconds(150))
                try? await Task.sleep(for: .milliseconds(500))
                exit(0)
            } catch {
                // Report asynchronous relaunch failures here so every triggering control gets visible feedback.
                diagLog.error("Failed to relaunch app: \(error.localizedDescription)")
                isRestarting = false
                let alert = NSAlert()
                alert.messageText = String(localized: "Couldn’t relaunch \(Constants.displayName)")
                alert.informativeText = String(
                    localized: "\(Constants.displayName) could not open a second copy of itself, so it stayed open and nothing changed. Quit and open it again to finish."
                )
                alert.runModal()
            }
        }
    }

    // MARK: - Observers

    /// Subscribe after bootstrap because immediate current-value emissions must not reach a half-built subsystem graph.
    private func installObservers() {
        cancellables.removeAll()

        observeActiveSpace()
        observeAppFocus()
        observeItemDrags()
        observeImageCacheTriggers()
        // Observation tracks owned-model reads through appState directly; no objectWillChange forwarding is needed.
        observeDisplayTopology()
    }

    /// Frontmost-app changes cover space notifications missed on secondary displays.
    /// Sample clicks immediately and again later because fullscreen notifications can precede window-server updates.
    private func observeActiveSpace() {
        let spaceSwitched = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .replace(with: ())
            .eraseToAnyPublisher()

        let appSwitched = NSWorkspace.shared
            .publisher(for: \.frontmostApplication)
            .replace(with: ())
            .eraseToAnyPublisher()

        let clicked = EventMonitor.publish(events: .leftMouseDown, scope: .universal)
            .throttle(for: .seconds(0.15), scheduler: DispatchQueue.main, latest: true)
            .flatMap { _ in
                Just(()).append(Just(()).delay(for: 0.1, scheduler: DispatchQueue.main))
            }
            .eraseToAnyPublisher()

        Publishers.MergeMany(spaceSwitched, appSwitched, clicked)
            .map { _ in Bridging.getActiveSpaceID() }
            .removeDuplicates()
            .sink { [weak self] spaceID in
                self?.activeSpace = SpaceInfo(spaceID: spaceID)
            }
            .store(in: &cancellables)
    }

    /// Mirrors "is Thaw the frontmost app" into navigationState, which the
    /// settings window and the Thaw bar both key their behaviour off.
    private func observeAppFocus() {
        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .receive(on: DispatchQueue.main)
            .map { $0 == .current }
            .removeDuplicates()
            .sink { [weak self] isFrontmost in
                self?.navigationState.isAppFrontmost = isFrontmost
            }
            .store(in: &cancellables)
    }

    /// Mirrors HIDEventManager drags for views, manually deduplicating Observation values.
    private func observeItemDrags() {
        let task = Task { @MainActor [weak self, hidEventManager] in
            let changes = Observations { hidEventManager.isDraggingMenuBarItem }
            var previous: Bool?
            for await isDragging in changes {
                guard let self else { return }
                guard isDragging != previous else { continue }
                let dragEnded = previous == true && !isDragging
                previous = isDragging
                isDraggingMenuBarItem = isDragging
                if dragEnded {
                    itemManager.noteUserMenuBarDragEnded()
                }
            }
        }
        AnyCancellable { task.cancel() }
            .store(in: &cancellables)
    }

    /// Refresh on frontmost Settings and once after bootstrap to populate the first draw.
    /// Observation flags change only on navigation, so no throttle is needed.
    private func observeImageCacheTriggers() {
        navigationStateObservationTask = Task { [weak self] in
            guard let self else { return }
            let changes = Observations { [navigationState] in
                (navigationState.isAppFrontmost, navigationState.isSettingsPresented)
            }
            for await (isAppFrontmost, isSettingsPresented) in changes {
                guard isAppFrontmost, isSettingsPresented else { continue }
                await self.refreshAllItemImages()
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            await self?.refreshAllItemImages()
        }
    }

    /// Use the visible-consumer guard: SCK's first capture retains roughly 10-20 MB, so wait until a consumer opens.
    private func refreshAllItemImages() async {
        await imageCache.recaptureIfWarranted()
        if imageCache.cacheSize > 15 {
            imageCache.logCacheStatus("Periodic update")
        }
    }

    /// A task-owned observer feeds a debounced AsyncStream because macOS Notification is not Sendable for notifications(named:).
    private func observeDisplayTopology() {
        let (topologyEvents, topologyContinuation) = AsyncStream<Void>.makeStream()
        let topologyTask = Task { @MainActor [weak self] in
            let observer = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in topologyContinuation.yield(()) }
            defer { NotificationCenter.default.removeObserver(observer) }
            for await _ in topologyEvents.debounce(for: .seconds(0.5)) {
                guard let self else { return }
                self.handleDisplayTopologyChange()
            }
        }
        cancellables.insert(AnyCancellable { topologyTask.cancel() })
    }

    /// The debounced body of observeDisplayTopology().
    private func handleDisplayTopologyChange() {
        let count = NSScreen.managedScreens.count
        defer { lastKnownScreenCount = count }
        if count < lastKnownScreenCount {
            diagLog.info("Display disconnected: refresh item cache + cleanup image cache")
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Wait for disconnect geometry to settle; a stale Control Center edge yields a negative overflow budget and persists hidden items as visible.
                itemManager.startSettlingPeriod(reason: "displayDisconnect")
                // Force item cache rebuild so displayID reflects current
                // display geometry (items moved to remaining display).
                await itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
                // Force image cache: remove entries for items no longer
                // present, trigger re-capture for current display.
                imageCache.performCacheCleanup()
                await imageCache.recaptureNow(sections: MenuBarSection.Name.allCases)
                diagLog.info("Cache refresh complete after display disconnect")
            }
        } else if count > lastKnownScreenCount {
            diagLog.info("Display connected: refresh item cache")
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Defer saved-layout restore until attached-display geometry settles, as on disconnect.
                itemManager.startSettlingPeriod(reason: "displayConnect")
                // Items keep their windowIDs when moving to new display.
                // Item cache rebuild picks up new items on the added display.
                await itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
                diagLog.info("Item cache refreshed after display connect")
            }
        }
    }

    // MARK: - Windows

    /// Emits the scene's window or nil when closed, starting with the current value and never finishing.
    /// Bridges trackedWindows Observation into a publisher.
    func windowPublisher(for id: ThawWindowIdentifier) -> some Publisher<NSWindow?, Never> {
        let subject = CurrentValueSubject<NSWindow?, Never>(trackedWindows[id])
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let changes = Observations { self.trackedWindows[id] }
            for await window in changes {
                subject.send(window)
            }
        }
        return subject.handleEvents(receiveCancel: { task.cancel() })
    }

    func prepareSettingsPresentation() {
        guard let id = navigationState.beginSettingsPresentation() else { return }
        imageCache.prepareForPresentation()
        // A failed or deferred scene request must not leave capture enabled.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.navigationState.finishSettingsPresentation(id)
        }
    }

    func openWindow(_ id: ThawWindowIdentifier) {
        if id == .settings {
            prepareSettingsPresentation()
        }
        Task { @MainActor [weak self] in
            guard let self else { return }

            if self.openWindows.contains(id) {
                self.diagLog.debug("Window \(id) already open (openWindows=\(self.openWindows)), activating existing window")
                self.activate(withPolicy: .regular)
                return
            }
            self.diagLog.debug("openWindow(\(id)) proceeding, openWindows=\(self.openWindows)")

            self.openWindows.insert(id)
            self.diagLog.debug("Opening window with id: \(id)")
            guard let openWindowAction = self.openWindowAction else {
                self.pendingOpenWindows.insert(id)
                self.diagLog.debug("Deferring window request until SwiftUI scene setup: \(id)")
                return
            }
            openWindowAction(id: id)

            try? await Task.sleep(for: .milliseconds(100))
            self.activate(withPolicy: .regular)
        }
    }

    func dismissWindow(_ id: ThawWindowIdentifier) {
        if id == .settings {
            navigationState.cancelSettingsPresentation()
            navigationState.isSettingsPresented = false
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.openWindows.remove(id)
            self.pendingOpenWindows.remove(id)
            self.diagLog.debug("Dismissing window with id: \(id)")
            self.dismissWindowAction?(id: id)
        }
    }

    /// onWindowChange supplies the live window, or nil after close and view teardown; mirror visibility into openWindows.
    func windowVisibilityChanged(id: ThawWindowIdentifier, window: NSWindow?) {
        guard let window else {
            trackedWindows[id] = nil
            windowVisibilityCancellables[id] = nil
            openWindows.remove(id)
            if id == .settings {
                navigationState.cancelSettingsPresentation()
                navigationState.isSettingsPresented = false
            }
            // The window's whole SwiftUI graph is now unreachable; make the
            // footprint reflect that rather than wait on malloc.
            MemoryReclaimer.scheduleRelief(reason: "\(id) closed")
            return
        }

        trackedWindows[id] = window
        openWindows.insert(id)
        windowVisibilityCancellables[id] = window.publisher(for: \.isVisible)
            .removeDuplicates()
            .sink { [weak self] isVisible in
                self?.handleWindowVisibilityChanged(id: id, isVisible: isVisible)
            }
    }

    /// Gates scene content because SwiftUI retains closed NSWindows and would otherwise retain every built view.
    /// Set before ordering the window front so content returns before display.
    func isWindowOpen(_ id: ThawWindowIdentifier) -> Bool {
        openWindows.contains(id)
    }

    /// Applies the side effects of a tracked window's visibility changing.
    private func handleWindowVisibilityChanged(id: ThawWindowIdentifier, isVisible: Bool) {
        if isVisible {
            openWindows.insert(id)
        } else {
            openWindows.remove(id)
            // Removing the id tears down scene content, allowing its memory pages to be reclaimed.
            MemoryReclaimer.scheduleRelief(reason: "\(id) closed")
        }

        guard id == .settings else { return }
        navigationState.isSettingsPresented = isVisible

        if isVisible {
            // Show consent only for completed tours without an update answer.
            // Unseen tours answer in the permissions window, even alongside restored Settings; wait for consent.
            if Constants.supportsSparkleUpdates,
               Defaults.bool(forKey: .hasSeenOnboarding),
               !Defaults.bool(forKey: .hasSeenUpdateConsent)
            {
                isUpdateConsentPresented = true
            } else if Defaults.bool(forKey: .hasSeenUpdateConsent) {
                startUpdaterIfNeeded()
            }

            // Select About after construction to avoid losing sidebar rendering; defer What's New while the consent sheet is open.
            if navigationState.isWhatsNewRequested, !isUpdateConsentPresented {
                navigationState.settingsNavigationIdentifier = .about
            }
        } else {
            deactivate(withPolicy: .accessory)
        }
    }

    /// Stores window actions from a live SwiftUI scene and fulfills any open
    /// request that arrived during application launch before scene setup.
    func registerWindowActions(openWindow: OpenWindowAction, dismissWindow: DismissWindowAction) {
        openWindowAction = openWindow
        dismissWindowAction = dismissWindow

        let pending = pendingOpenWindows
        pendingOpenWindows.removeAll()
        for id in pending {
            diagLog.debug("Fulfilling pending window request for id: \(id)")
            openWindow(id: id)
        }
    }

    // MARK: - Activation and permissions

    /// Centralizes policy changes for focus-drop attribution; DiagLog avoids stack-capture cost when diagnostics are off.
    private func applyActivationPolicy(
        _ policy: NSApplication.ActivationPolicy,
        callerFile: String = #fileID,
        callerLine: Int = #line
    ) {
        diagLog.debug(
            "focus-trace setActivationPolicy \(policy.rawValue) from \(callerFile):\(callerLine) stack=\(Thread.callStackSymbols.prefix(8).joined(separator: " | "))"
        )
        NSApp.setActivationPolicy(policy)
    }

    func restoreAccessoryPolicyIfUnused(
        callerFile: String = #fileID,
        callerLine: Int = #line
    ) {
        diagLog.debug(
            "focus-trace restoreAccessoryPolicyIfUnused from \(callerFile):\(callerLine) stack=\(Thread.callStackSymbols.prefix(8).joined(separator: " | "))"
        )
        guard NSApp.activationPolicy() == .regular,
              openWindows.isEmpty,
              pendingOpenWindows.isEmpty,
              !navigationState.isSettingsPresented,
              !navigationState.isThawBarPresented,
              !navigationState.isSearchPresented,
              !menuBarManager.layoutEditorPanel.isShown,
              !menuBarManager.isHidingApplicationMenus,
              NSApp.modalWindow == nil,
              !NSApp.windows.contains(where: {
                  ($0.isVisible || $0.isMiniaturized) && ($0.canBecomeKey || $0.canBecomeMain)
              })
        else { return }

        diagLog.debug("No windows or panels need activation, switching to accessory policy")
        applyActivationPolicy(.accessory)
    }

    /// Reassert activation through NSRunningApplication after policy changes because NSApp.activate alone is unreliable.
    /// Prefer handoff from the frontmost app to avoid a Dock bounce.
    func activate(
        withPolicy policy: NSApplication.ActivationPolicy? = nil,
        callerFile: String = #fileID,
        callerLine: Int = #line
    ) {
        diagLog.debug(
            "focus-trace activate policy=\(String(describing: policy)) from \(callerFile):\(callerLine) stack=\(Thread.callStackSymbols.prefix(8).joined(separator: " | "))"
        )

        if let policy {
            applyActivationPolicy(policy)
        }

        NSApp.activate(ignoringOtherApps: true)

        Task {
            try? await Task.sleep(for: .milliseconds(50))
            let frontmost = NSWorkspace.shared.frontmostApplication
            diagLog.debug(
                "focus-trace activate re-assert after 50ms frontmost=\(frontmost?.bundleIdentifier ?? "nil") stack=\(Thread.callStackSymbols.prefix(8).joined(separator: " | "))"
            )
            if let frontmost {
                NSRunningApplication.current.activate(from: frontmost)
            } else {
                NSRunningApplication.current.activate()
            }
        }
    }

    /// Gives up focus, optionally dropping back to an accessory process on the
    /// way out so the app leaves the Dock and the app switcher.
    func deactivate(
        withPolicy policy: NSApplication.ActivationPolicy? = nil,
        callerFile: String = #fileID,
        callerLine: Int = #line
    ) {
        diagLog.debug(
            "focus-trace deactivate policy=\(String(describing: policy)) from \(callerFile):\(callerLine) stack=\(Thread.callStackSymbols.prefix(8).joined(separator: " | "))"
        )

        if let policy {
            applyActivationPolicy(policy)
        }
        NSApp.deactivate()
    }

    /// Whether the app currently holds the grant named by key.
    func isPermissionGranted(_ key: AppPermissions.PermissionKey) -> Bool {
        switch key {
        case .accessibility: permissions.accessibility.hasPermission
        case .screenRecording: permissions.screenRecording.hasPermission
        case .fullDiskAccess: permissions.fullDiskAccess.hasPermission
        case .controlCenterAppList: permissions.controlCenterAppList.hasPermission
        }
    }
}
