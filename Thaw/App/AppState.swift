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
import ThawCapture
import ThawUI

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

    /// Whether profiles are on. Held here so the menus and the Profiles pane observe one switch.
    let profilesFeature = ProfilesFeature()

    // Menu bar stack. Set up in dependency order; see bootstrapTask.

    /// The sections, their control items, and the show/hide state machine.
    let menuBarManager = MenuBarManager()

    /// Shared by the menu bar manager, which acts on a display move, and the
    /// event taps, which ask for a check.
    private let activeDisplayWatcher = ActiveMenuBarDisplayWatcher()

    /// Settles screen-parameter changes into one numbered snapshot.
    let displayEnvironment = DisplayEnvironment()

    /// Runs the settle a display change owes, and the image cleanup after a removal, once per settled generation.
    @ObservationIgnored lazy var displayChangeCoordinator = DisplayChangeCoordinator(
        environment: displayEnvironment,
        effects: MenuBarDisplayChangeEffects(itemManager: itemManager, repairs: itemManager.repairs, imageCache: imageCache, displaySettings: settings.displaySettings, profiles: profileManager, presentationMonitor: presentationMonitor, menuBarManager: menuBarManager)
    )

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

    /// Owner of the user's menu bar spacer items.
    let spacerManager = MenuBarSpacerManager()
    let screenCorners = ScreenCorners()
    let itemHints = ItemHints()
    let groupFolders = GroupFolders()

    /// Owner of user-authored menu bar item groups.
    let itemGroupManager = MenuBarItemGroupManager()

    /// Saves layout changes into the active profile when it keeps them.
    @ObservationIgnored private(set) lazy var profileLayoutKeeper = ProfileLayoutKeeper(
        profileManager: profileManager,
        itemManager: itemManager,
        groupManager: itemGroupManager
    )

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

    /// The panel Thaw's own icon raises in place of its status menu. Nothing
    /// is constructed until the first press with it on.
    let controlItemPanel = ControlItemPanelController()

    /// Reads the camera and microphone for Zen Mode, using only public CoreAudio and CoreMediaIO state.
    let recordingWatchManager = RecordingWatchManager()

    /// Launches the modules shipped with Thaw or installed beside it.
    let moduleHost = ModuleHost(environment: .live())

    let applicationMenuCover = ApplicationMenuCover()

    /// Settings in a process of its own, when SettingsInOwnProcess is set.
    @ObservationIgnored
    private(set) lazy var settingsProcessHost = SettingsProcessHost(app: settingsProcessAppSide())

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

    /// Track open windows to prevent duplicates.
    var openWindows = Set<ThawWindowIdentifier>()

    /// Whether any Thaw window is open.
    var hasOpenWindow: Bool {
        !openWindows.isEmpty
    }

    /// Live windows keyed by identifier, released after close teardown completes.
    var trackedWindows = [ThawWindowIdentifier: NSWindow]()

    /// AppKit window delegates keyed by identifier.
    @ObservationIgnored var windowDelegates = [ThawWindowIdentifier: ThawWindowDelegate]()

    /// Delayed teardown tasks armed when a window closes so rapid reopens skip full view teardown.
    @ObservationIgnored var windowTeardownTasks = [ThawWindowIdentifier: Task<Void, Never>]()

    /// Overridable factory for unit tests verifying lazy creation, grace reuse, and teardown.
    @ObservationIgnored var windowFactory: @MainActor (ThawWindowIdentifier, AppState, NSWindowDelegate) -> NSWindow =
        AppState.defaultMakeManagedWindow

    static let windowTeardownDelay: Duration = .seconds(2)

    // MARK: - Private state

    /// Holds the subscriptions made by installObservers(). Emptied before
    /// they are remade, so the observers can never end up doubled.
    var cancellables = Set<AnyCancellable>()

    /// Watches navigationState's observable focus and Settings visibility.
    var navigationStateObservationTask: Task<Void, Never>?

    /// Prevent repeated restart attempts.
    var isRestarting = false

    func updateActiveSpace(_ spaceID: Int) {
        activeSpace = SpaceInfo(spaceID: spaceID)
    }

    func updateIsDraggingMenuBarItem(_ isDragging: Bool) {
        isDraggingMenuBarItem = isDragging
    }

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

        displayEnvironment.start()
        settings.performSetup(with: self)
        menuBarManager.performSetup(with: self, activeDisplayWatcher: activeDisplayWatcher, displays: displayEnvironment)
        // A refused preferences watcher stays stopped; recreate it after either a table-file grant or Full Disk Access.
        permissions.onPermissionTransition = { [weak self] permission, granted in
            guard let self, granted, permission === permissions.fullDiskAccess else { return }
            (menuBarManager.sectionController as? RuntimeSectionController)?.restartPreferencesWatcher()
        }
        diagLog.debug("bootstrap: settings and menuBarManager setup complete")

        appearanceManager.performSetup(with: self, displayInvalidations: displayEnvironment.invalidations, displaySettlements: displayEnvironment.settlements)
        hidEventManager.performSetup(with: self, activeDisplayWatcher: activeDisplayWatcher)
        diagLog.debug("bootstrap: starting itemManager setup")
        await itemManager.performSetup(with: self)
        diagLog.debug("bootstrap: itemManager setup scheduled, invalidating menuBarHeightCache")
        NSScreen.invalidateMenuBarGeometryCache()
        diagLog.debug("bootstrap: starting imageCache setup")
        imageCache.activate(with: self)
        alertRevealWatcher.performSetup(with: self)
        presentationMonitor.performSetup(with: self)
        spacerManager.performSetup(with: self)
        screenCorners.performSetup(with: self, displaySettlements: displayEnvironment.settlements)
        itemHints.performSetup(with: self)
        groupFolders.performSetup(with: self)
        diagLog.debug("bootstrap: imageCache setup complete")
        updatesManager.performSetup(with: self)
        if UpdatesManager.startsAtLaunch(
            supportsSparkle: Constants.supportsSparkleUpdates,
            hasSeenConsent: Defaults.bool(forKey: .hasSeenUpdateConsent),
            isSettingsProcess: SettingsProcessApp.isRequested
        ) {
            startUpdaterIfNeeded()
        }
        userNotificationManager.performSetup(with: self)
        profileManager.performSetup(with: self)
        itemManager.repairs.onUserLayoutChange = { [weak self] in self?.profileLayoutKeeper.noteUserLayoutChange() }
        itemManager.savedOrderMirrorGate.observe(displayInvalidations: displayEnvironment.invalidations)
        profilesFeature.onChange = { [weak profileManager] in profileManager?.rebuildProfileHotkeys() }
        controlCommandObserver.performSetup(with: self)
        controlStatePublisher.performSetup(with: self)
        swapBarManager.performSetup(with: self, displaySettlements: displayEnvironment.settlements)
        controlItemPanel.performSetup(with: self)
        recordingWatchManager.performSetup(with: self)
        applicationMenuCover.performSetup(with: self)
        moduleHost.startObservingTerminations()
        Task { await moduleHost.startAll() }

        installObservers()
        MemoryReclaimer.start()
        diagLog.debug("bootstrap: AppState setup sequence complete")
    }

    /// Called by AppDelegate and again after first-launch permission setup.
    /// - Parameter granted: True runs bootstrap with required grants; false keeps subsystems inert and opens permissions.
    func launch(withPermissions granted: Bool) {
        guard granted else {
            if ReducedModeController.isChosen {
                dismissWindow(.permissions)
                ReducedModeController.shared.start(with: self)
                return
            }
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
            guard await ChangelogDocument.load(allowFetch: allowFetch, info: .thaw).document?.newestRelease != nil else { return }
            activate(withPolicy: .regular)
            openWindow(.whatsNew)
        }
    }

    /// Allows explicit starting of the updater from UI flows.
    func startUpdaterIfNeeded() {
        updatesManager.startUpdaterIfNeeded()
    }
}
