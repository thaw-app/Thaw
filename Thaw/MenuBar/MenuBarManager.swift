//
//  MenuBarManager.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AsyncAlgorithms
import Combine
import MenuBarModel
import Observation
import PlatformRuntimeKit
import SwiftUI
import ThawCapture

/// Owns sections, panels, per-item hotkeys, and color samples, reacting to system and setting changes after setup.
/// AppState owns this manager; methods stop when the weak back reference is gone.
@MainActor
@Observable
final class MenuBarManager {
    /// Information for the menu bar's average color on the active screen.
    private(set) var averageColorInfo: MenuBarAverageColorInfo?

    /// Per-screen average colors for multi-monitor adaptive backgrounds.
    private(set) var averageColors: [CGDirectDisplayID: MenuBarAverageColorInfo] = [:]

    /// Per-screen dominant-color palettes for the adaptive gradient tint.
    private(set) var wallpaperPalettes: [CGDirectDisplayID: WallpaperPalette] = [:]

    /// System hiding or auto-hiding, independent of Thaw's concealment.
    private(set) var isMenuBarHiddenBySystem = false

    /// Persisted _HIHideMenuBar value, unlike isMenuBarHiddenBySystem which also reflects transient app presentation options.
    private(set) var isMenuBarHiddenBySystemUserDefaults = false

    /// Pause hover after an explicit toggle so it cannot undo the user; resume when the pointer leaves.
    var showOnHoverAllowed = true {
        didSet {
            guard oldValue != showOnHoverAllowed else { return }
            diagLog.debug("hover: \(showOnHoverAllowed ? "allowed again" : "paused")")
        }
    }

    /// Timestamp of the last time a section was shown.
    private(set) var lastShowTimestamp: ContinuousClock.Instant?

    /// Track visibility to sample live colors only while settings needs them.
    private var settingsWindow: NSWindow?

    @ObservationIgnored
    private let diagLog = DiagLog(category: "MenuBarManager")

    /// Weak because AppState owns this manager.
    @ObservationIgnored
    private weak var appState: AppState?

    /// Engine-facing settings, assigned at setup with shared defaults beforehand; see MenuBarEngineConfiguration.
    private var configuration: any MenuBarEngineConfiguration = AppSettings.engineDefaults

    /// Replaced wholesale when observers are rebuilt.
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    /// Block nudges only during reveal reflow, not a settled reveal, so hidden moves retain their cursor-free path.
    @ObservationIgnored
    private var lastRevealTransition: Date?

    /// Generous reflow window; observed settling takes tens of milliseconds.
    private static let revealReflowSettleWindow: TimeInterval = 0.5

    /// Observes DisplaySettingsManager.configurations through Observation, not Combine.
    @ObservationIgnored
    private var displayConfigurationsObservationTask: Task<Void, Never>?

    /// Cancel delayed focus rehide on a newer focus change or user reveal so it cannot override new state.
    @ObservationIgnored
    private var focusChangeRehideTask: Task<Void, Never>?

    deinit {
        displayConfigurationsObservationTask?.cancel()
        focusChangeRehideTask?.cancel()
    }

    /// Menu-opening hotkeys keyed by uniqueIdentifier, mirroring ProfileManager's per-profile bindings.
    private(set) var itemHotkeys: [String: Hotkey] = [:]

    /// Reverse map from a hotkey instance to the item identifier it opens.
    /// Read by Hotkey.Listener when an openMenuBarItem hotkey fires.
    var hotkeyItemMap: [ObjectIdentifier: String] = [:]

    /// Keyed by identifier so one binding's persistence observer can be removed independently.
    @ObservationIgnored
    private var itemHotkeyCancellables = [String: AnyCancellable]()

    /// Cancellable for the periodic average-color refresh, active only while settings is visible.
    @ObservationIgnored
    private var averageColorRefreshCancellable: AnyCancellable?

    /// Re-subscribe to isVisible KVO for each new non-nil settings window.
    @ObservationIgnored
    private var settingsWindowVisibilityCancellable: AnyCancellable?

    /// Cancellable for the periodic average-color refresh when adaptive background is active.
    @ObservationIgnored
    private var adaptiveColorRefreshCancellable: AnyCancellable?

    /// Wallpaper changes retint immediately rather than waiting for a poll.
    @ObservationIgnored
    private let wallpaperChangeMonitor = WallpaperChangeMonitor()

    /// The adaptive poll's cadence; the palette fallback derives from it rather than running its own timer.
    private static let adaptiveRefreshInterval: TimeInterval = 30
    private static let adaptiveRefreshTolerance: TimeInterval = 5

    /// The shortest gap between two adaptive polls, so each poll finds the palette due however often strips are sampled.
    static let paletteFallbackInterval: Duration = .seconds(adaptiveRefreshInterval - adaptiveRefreshTolerance)

    /// Advances when the wallpaper may have been replaced; palettes captured under an older value are stale.
    @ObservationIgnored
    private var wallpaperGeneration = 0

    /// What each published palette was captured from and when, keyed by display.
    @ObservationIgnored
    private var paletteRefreshStates: [CGDirectDisplayID: PaletteRefreshState] = [:]

    /// Generation checks prevent slow captures from overwriting newer samples or wake-restored colors.
    @ObservationIgnored
    private var captureGeneration = 0

    /// Per-screen colors cached before sleep, restored on wake to avoid stale/white flash.
    @ObservationIgnored
    private var sleepColorCache: [CGDirectDisplayID: MenuBarAverageColorInfo]?

    /// Skip sampling sleeping displays: captures cost work and do not reflect the wallpaper.
    @ObservationIgnored
    private var displaysAreAsleep = false

    /// Polling state for adaptive wake stabilization.
    @ObservationIgnored
    private var wakePollTimer: AnyCancellable?
    private var wakePollPrevColors: [CGDirectDisplayID: MenuBarAverageColorInfo]?
    private var wakePollStableCount = 0
    private var wakePollDidChange = false
    private var wakePollStartTime: Date?

    /// Thaw has replaced the front app's menus with its own empty menus.
    private(set) var isHidingApplicationMenus = false

    /// Manual URL/hotkey hiding must not be undone by automatic section state.
    private var isManuallyHidingApplicationMenus = false
    private var nativeMenuBarStateChangedAt: ContinuousClock.Instant?

    let thawBarPanel = ThawBarPanel()

    let searchPanel = MenuBarSearchPanel()

    /// Standalone appearance editor for changes without opening Settings.
    let appearanceEditorPanel = MenuBarAppearanceEditorPanel()

    let layoutEditorPanel = MenuBarLayoutEditorPanel()

    /// Non-optional platform controller behind an interface so app callers need no platform type.
    private(set) var sectionController: any MenuBarSectionControlling = InertSectionController()

    /// Concrete access for platform-typed operations, exposed to callers only through this manager.
    private var runtimeSectionController: RuntimeSectionController?

    /// Preassign stand-ins before creation so they are not born into a concealed section.
    func assignSection(_ section: MenuBarSection.Name, identifier: String) {
        runtimeSectionController?.setSection(section, identifier: identifier)
    }

    /// Native-hidden apps intentionally publish no items; kept off the ABI-locked section-controller protocol.
    var nativeHiddenBundleIDs: Set<String> {
        runtimeSectionController?.nativeHiddenBundleIDs ?? []
    }

    /// Apps native hiding could not switch off; their icons stay on the bar.
    var nativeUntrackedBundleIDs: Set<String> {
        runtimeSectionController?.nativeUntrackedBundleIDs ?? []
    }

    let nativeAppHidingExperiment = NativeAppHidingExperiment()

    /// Per-extra opt-in stand-ins for Apple extras removed in hidden sections; see SystemExtraTakeoverCoordinator.
    let systemExtraTakeover = SystemExtraTakeoverCoordinator()

    /// Panels observe reveals without holding a platform type; emits nothing without an engine.
    var revealedSectionChanges: AnyPublisher<MenuBarSectionName?, Never> {
        runtimeSectionController?.$revealedSection.eraseToAnyPublisher()
            ?? Empty(completeImmediately: false).eraseToAnyPublisher()
    }

    /// Authored membership and order changes, independent of AX cache refresh.
    var sectionLayoutChanges: AnyPublisher<Void, Never> {
        guard let controller = runtimeSectionController else {
            return Empty(completeImmediately: false).eraseToAnyPublisher()
        }
        return Publishers.CombineLatest(
            controller.$sectionAssignment.removeDuplicates(),
            controller.$sectionItemOrder.removeDuplicates()
        )
        .map { _ in () }
        .eraseToAnyPublisher()
    }

    /// Reports the platform's refusal if it cannot assign the group.
    @discardableResult
    func setSection(
        _ section: MenuBarSectionName,
        items: [MenuBarItem],
        atomically: Bool = false
    ) -> MenuBarGroupMoveRefusal? {
        runtimeSectionController?
            .setSection(section, items: items, atomically: atomically)
            .map(MenuBarGroupMoveRefusal.init)
    }

    /// Covers hidden items that flash during Clock or Notification Center shortcut bridging.
    let clockBridgeCover = ClockBridgeCover()

    /// What the bar is drawn over, for anything that paints over the bar.
    let backdrop = MenuBarBackdrop()

    /// The live left edge of the visible run, for anything drawn against it.
    let leadingEdgeWatcher = MenuBarLeadingEdgeWatcher()

    /// Distinguishes persistent "Always show hidden items" reveals from temporary user toggles.
    private var isAlwaysShowRevealActive = false

    var shouldDeferBarMutation: Bool {
        guard let nativeMenuBarStateChangedAt else { return false }
        return nativeMenuBarStateChangedAt.duration(to: .now) < Constants.MenuBarTuning.nativeMenuBarMutationSettle
    }

    /// Fixed sections, built once and never reordered; access by section(withName:).
    let sections = [
        MenuBarSection(name: .visible),
        MenuBarSection(name: .hidden),
        MenuBarSection(name: .alwaysHidden),
    ]

    var hasVisibleSection: Bool {
        sections.contains { !$0.isHidden }
    }

    /// Native or Thaw overflow forces Thaw Bar without changing the display preference.
    /// Ejected items cannot fit an inline reveal; see MenuBarSection.forcesThawBarForNotchOverflow.
    func shouldUseThawBar(for displayID: CGDirectDisplayID) -> Bool {
        return appState?.settings.displaySettings.useThawBar(for: displayID) == true
            || sectionController.isNativeOverflowActive(on: displayID) == true
            || MenuBarSection.forcesThawBarForNotchOverflow(
                overflowEnabled: configuration.enableMenuBarItemOverflow,
                // No preference exists yet; keep the parameter to add one without changing the rule or tests.
                useThawBarOnOverflow: true,
                hasEjectedItems: !sectionController.overflowHiddenIdentifiers.isEmpty
            )
    }

    /// Adaptive backgrounds and tints need continuing color samples.
    private var isAdaptiveAppearanceActive: Bool {
        adaptiveCaptureRequirements?.isAdaptive ?? false
    }

    /// Sample only for visible capture UI; closed surfaces retain cached colors.
    private var adaptiveCaptureRequirements: AdaptiveCaptureRequirements? {
        guard let appState, appState.navigationState.hasVisibleCaptureUI else {
            return nil
        }
        return AdaptiveCaptureRequirements(
            configuration: appState.appearanceManager.configuration.current,
            thawBarConfiguration: appState.navigationState.isThawBarPresented || settingsWindow?.isVisible == true
                ? appState.appearanceManager.configuration.resolvedThawBarAppearance.fillConfiguration : nil
        )
    }

    // MARK: - Setup

    /// Captured at launch setup so smart rehide reads menu-open state without reaching through the item manager.
    private var menuOpenMonitor: MenuOpenMonitor?

    func performSetup(with appState: AppState) {
        self.appState = appState
        configuration = appState.settings
        menuOpenMonitor = appState.itemManager.menuOpenMonitor
        installObservers()
        thawBarPanel.performSetup(with: appState)
        searchPanel.performSetup(with: appState)
        appearanceEditorPanel.performSetup(with: appState)
        layoutEditorPanel.performSetup(with: appState)
        for section in sections {
            section.performSetup(with: appState)
        }
        // Divider reflow cannot hide items; a separate assignment model drives the restriction set.
        nativeAppHidingExperiment.recoverPreviousSession()
        systemExtraTakeover.recoverPreviousSession()
        // Recovery and overflow need notch coverage kept current across display changes.
        MenuBarNotchGeometry.refresh()
        let controller = RuntimeSectionController(
            context: RuntimeSectionContextAdapter(appState: appState)
        )
        controller.start()
        sectionController = controller
        runtimeSectionController = controller
        nativeAppHidingExperiment.start(controller: controller, settings: appState.settings.advanced)
        systemExtraTakeover.start(controller: controller, settings: appState.settings.advanced) { [weak appState] identifier in
            guard let itemManager = appState?.itemManager,
                  itemManager.knownItemIdentifiers.insert(identifier).inserted
            else {
                return
            }
            itemManager.persistKnownItemIdentifiers()
        }
        MenuBarPresentationProvider.startDiagnosticSessionIfGated()
        leadingEdgeWatcher.performSetup(with: appState)
        backdrop.performSetup(with: appState)
        clockBridgeCover.performSetup(with: appState)
        synchronizeAlwaysShowHiddenItems()
        rebuildItemHotkeys()
    }

    // MARK: - Observers

    /// Replace the observer bag as a complete set so rebuilds do not leave partial subscriptions.
    private func installObservers() {
        averageColorRefreshCancellable?.cancel()
        averageColorRefreshCancellable = nil

        var bag = Set<AnyCancellable>()
        observeSystemMenuBarPresentation(into: &bag)
        observeSystemAutohideDefault(into: &bag)
        observeFocusChangeRehide(into: &bag)
        observeSettingsWindowReference(into: &bag)
        observeUserSettings(into: &bag)
        observeSettingsWindowVisibility(into: &bag)
        observeEnvironmentChanges(into: &bag)
        observeDisplaySleepCycle(into: &bag)
        observeAdaptiveAppearance(into: &bag)
        observeApplicationMenuHiding(into: &bag)
        observeRevealTransitions(into: &bag)
        cancellables = bag
    }

    /// Timestamp system presentation changes so menu bar mutations can wait for settling.
    private func observeSystemMenuBarPresentation(into bag: inout Set<AnyCancellable>) {
        NSApp.publisher(for: \.currentSystemPresentationOptions)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] options in
                guard let self else {
                    return
                }
                let hidden = options.contains(.hideMenuBar) || options.contains(.autoHideMenuBar)
                if hidden != isMenuBarHiddenBySystem {
                    nativeMenuBarStateChangedAt = .now
                }
                isMenuBarHiddenBySystem = hidden
            }
            .store(in: &bag)
    }

    /// _HIHideMenuBar is true for the Always and On Desktop Only auto-hide options.
    private func observeSystemAutohideDefault(into bag: inout Set<AnyCancellable>) {
        DistributedNotificationCenter.default()
            .publisher(for: DistributedNotificationCenter.menuBarHidingChangedNotification)
            .replace(with: ())
            .prepend(())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else {
                    return
                }
                isMenuBarHiddenBySystemUserDefaults = Defaults.globalDomain["_HIHideMenuBar"] as? Bool ?? false
            }
            .store(in: &bag)
    }

    private func observeFocusChangeRehide(into bag: inout Set<AnyCancellable>) {
        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            // Skip the initial app value to avoid an expensive menu-open scan before the first cache pass.
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleFocusChangeRehide()
            }
            .store(in: &bag)
    }

    /// Focus rehide leaves sections alone while the pointer is over either bar, since the user is still using them.
    private func scheduleFocusChangeRehide() {
        guard let appState, configuration.autoRehide else {
            return
        }
        switch configuration.rehideStrategy {
        case .focusedApp, .smart:
            break
        case .timed:
            return
        }
        guard
            let hiddenSection = section(withName: .hidden),
            let screen = appState.hidEventManager.bestScreen(appState: appState),
            !appState.hidEventManager.isMouseInsideMenuBar(appState: appState, screen: screen),
            !appState.hidEventManager.isMouseInsideThawBar(appState: appState)
        else {
            return
        }
        focusChangeRehideTask?.cancel()
        focusChangeRehideTask = Task {
            await self.rehideAfterFocusChange(hiddenSection, appState: appState)
        }
    }

    /// After the rehide interval, allow a half-second reveal grace period because focus often changes on the reveal click.
    /// Smart rehide also waits while any item's menu is open.
    private func rehideAfterFocusChange(_ section: MenuBarSection, appState _: AppState) async {
        do {
            try await Task.sleep(for: .seconds(configuration.rehideInterval))
        } catch {
            return
        }

        // A reveal can cancel this task even after sleep returns.
        guard !Task.isCancelled else { return }

        if let lastShow = lastShowTimestamp, lastShow.duration(to: .now) < .milliseconds(500) {
            diagLog.debug("Skipping rehide due to grace period")
            return
        }

        if
            configuration.rehideStrategy == .smart,
            await menuOpenMonitor?.isAnyMenuOpen() == true
        {
            return
        }

        section.hide()
    }

    private func observeSettingsWindowReference(into bag: inout Set<AnyCancellable>) {
        appState?.windowPublisher(for: .settings)
            .sink { [weak self] window in
                self?.settingsWindow = window
            }
            .store(in: &bag)
    }

    private func observeUserSettings(into bag: inout Set<AnyCancellable>) {
        guard let appState else {
            return
        }

        // Observation delivers the current display configurations before later changes.
        displayConfigurationsObservationTask?.cancel()
        displayConfigurationsObservationTask = Task { @MainActor [weak self, displaySettings = appState.settings.displaySettings] in
            let changes = Observations { displaySettings.configurations }
            for await _ in changes {
                guard let self else { return }
                synchronizeAlwaysShowHiddenItems()
                updateControlItemStates()
            }
        }

        // Debounce cache changes so new items become assignable without churning hotkey registrations each tick.
        let hotkeyTask = Task { @MainActor [weak self, itemManager = appState.itemManager] in
            let changes = Observations { itemManager.itemCache }
            for await _ in changes.debounce(for: .seconds(0.5)) {
                guard let self else { return }
                rebuildItemHotkeys()
            }
        }
        AnyCancellable { hotkeyTask.cancel() }
            .store(in: &bag)
    }

    /// Poll colors while settings previews them because macOS posts no desktop-picture notification.
    /// Stop sampling and the timer when the window is dismissed.
    private func observeSettingsWindowVisibility(into bag: inout Set<AnyCancellable>) {
        // Observe the window reference, then re-subscribe to its separate isVisible KVO stream for each non-nil window.
        let task = Task { @MainActor [weak self] in
            let changes = Observations { self?.settingsWindow }
            for await window in changes {
                guard let self else { return }
                guard let window else {
                    // KVO retains the window; drop the subscription to release the closed window and its views.
                    settingsWindowVisibilityCancellable = nil
                    averageColorRefreshCancellable?.cancel()
                    averageColorRefreshCancellable = nil
                    continue
                }
                subscribeToSettingsWindowVisibility(of: window)
            }
        }
        AnyCancellable { task.cancel() }
            .store(in: &bag)
    }

    private func subscribeToSettingsWindowVisibility(of window: NSWindow) {
        settingsWindowVisibilityCancellable = window.publisher(for: \.isVisible)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                guard let self else { return }
                guard isVisible else {
                    averageColorRefreshCancellable?.cancel()
                    averageColorRefreshCancellable = nil
                    return
                }
                updateAverageColorInfo()
                averageColorRefreshCancellable = Timer.publish(every: 60, tolerance: 10, on: .main, in: .default)
                    .autoconnect()
                    .sink { [weak self] _ in
                        guard let self, !displaysAreAsleep else { return }
                        updateAverageColorInfo()
                    }
            }
    }

    /// Space and display changes can replace the wallpaper; resample only with an active consumer.
    private func observeEnvironmentChanges(into bag: inout Set<AnyCancellable>) {
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
            // Count it even with no consumer, so a palette kept from before is not reused later.
            wallpaperGeneration += 1
            guard settingsWindow?.isVisible == true || isAdaptiveAppearanceActive else {
                return
            }
            updateAverageColorInfo()
        }
        .store(in: &bag)
    }

    /// Restore banked colors immediately on wake to avoid a white flash, then poll for changed, settled samples.
    /// Screen sleep/wake notifications cover both display-only sleep and system sleep.
    private func observeDisplaySleepCycle(into bag: inout Set<AnyCancellable>) {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.screensDidSleepNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                displaysAreAsleep = true
                sleepColorCache = averageColors
            }
            .store(in: &bag)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                displaysAreAsleep = false
                restoreColorsAfterWake()
            }
            .store(in: &bag)
    }

    /// Refresh without stabilization polling if no pre-sleep colors were banked.
    private func restoreColorsAfterWake() {
        guard isAdaptiveAppearanceActive else {
            return
        }
        guard let cache = sleepColorCache else {
            updateAverageColorInfo()
            return
        }

        // Invalidate pre-sleep captures so they cannot overwrite the restored colors.
        captureGeneration += 1
        averageColors = cache
        if
            let displayID = NSScreen.screenWithActiveMenuBar?.displayID,
            let cached = cache[displayID]
        {
            averageColorInfo = cached
        }

        wakePollPrevColors = nil
        wakePollStableCount = 0
        wakePollDidChange = false
        wakePollStartTime = Date()
        wakePollTimer = Timer.publish(every: 1, tolerance: 0.1, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.advanceWakeStabilizationPoll()
                }
            }
    }

    /// Await capture so comparisons use this tick's colors rather than exhausting the poll budget on stale values.
    /// Dropping wakePollTimer ends polling and releases the subscription.
    private func advanceWakeStabilizationPoll() async {
        let elapsed = wakePollStartTime.map { Date().timeIntervalSince($0) } ?? 0
        if elapsed >= 10 {
            endWakeStabilizationPoll()
            return
        }

        await updateAverageColorInfoAsync()
        let sampled = averageColors

        if !wakePollDidChange, let cache = sleepColorCache, sampled != cache {
            wakePollDidChange = true
        }

        if wakePollDidChange {
            if let previous = wakePollPrevColors, previous == sampled {
                wakePollStableCount += 1
                if wakePollStableCount >= 1 {
                    endWakeStabilizationPoll()
                    return
                }
            } else {
                wakePollStableCount = 0
            }
        }

        wakePollPrevColors = sampled
    }

    private func endWakeStabilizationPoll() {
        sleepColorCache = nil
        wakePollTimer = nil
    }

    /// Retry initial adaptive capture while WindowServer settles at launch; later polling is slow to catch gradual changes.
    private func observeAdaptiveAppearance(into bag: inout Set<AnyCancellable>) {
        guard appState != nil else {
            return
        }
        // Deduplicate derived capture requirements across Observation updates.
        let task = Task { @MainActor [weak self] in
            let changes = Observations { [weak self] in
                self?.adaptiveCaptureRequirements ?? AdaptiveCaptureRequirements(configuration: .defaultConfiguration)
            }
            var previous: AdaptiveCaptureRequirements?
            for await requirements in changes {
                guard let self else { return }
                let action = Self.adaptiveRefreshAction(from: previous, to: requirements)
                previous = requirements
                switch action {
                case .unchanged:
                    continue
                case .recapture:
                    // Gradient tint needs a new palette now; waiting for the poll would leave the average-color fallback.
                    captureAdaptiveColorWithRetry()
                case .start:
                    captureAdaptiveColorWithRetry()
                    adaptiveColorRefreshCancellable = Timer.publish(
                        every: Self.adaptiveRefreshInterval,
                        tolerance: Self.adaptiveRefreshTolerance,
                        on: .main,
                        in: .default
                    )
                    .autoconnect()
                    .sink { [weak self] _ in
                        // Skip sleep ticks; wake restores banked colors and runs its own poll.
                        guard let self, !displaysAreAsleep else { return }
                        updateAverageColorInfo()
                    }
                    wallpaperChangeMonitor.onChange = { [weak self] in
                        self?.wallpaperGeneration += 1
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
        AnyCancellable { task.cancel() }
            .store(in: &bag)
    }

    /// Control state changes signal section reveals and concealment, requiring menu visibility reconciliation.
    private func observeApplicationMenuHiding(into bag: inout Set<AnyCancellable>) {
        Publishers.MergeMany(sections.map(\.controlItem.$state))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reconcileApplicationMenuVisibility()
            }
            .store(in: &bag)
    }

    /// Do not take app menus when Thaw Bar presents elsewhere, the system hides the bar, or fullscreen/settings needs them.
    private func reconcileApplicationMenuVisibility() {
        guard let appState else {
            return
        }

        let activeDisplayID = (NSScreen.screenWithActiveMenuBar ?? NSScreen.main)?.displayID ?? CGMainDisplayID()
        guard
            configuration.hideApplicationMenus,
            !shouldUseThawBar(for: activeDisplayID),
            !isMenuBarHiddenBySystem,
            !appState.activeSpace.isFullscreen,
            !appState.navigationState.isSettingsPresented
        else {
            return
        }

        let hiddenSection = section(withName: .hidden)
        let alwaysHiddenSection = section(withName: .alwaysHidden)
        let isShowingHidden = hiddenSection.map { !$0.isHidden } ?? false
        let isShowingAlwaysHidden = alwaysHiddenSection.map { !$0.isHidden } ?? false

        guard isShowingHidden || isShowingAlwaysHidden else {
            if isHidingApplicationMenus, !isManuallyHidingApplicationMenus {
                showApplicationMenus()
            }
            return
        }

        guard let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main else {
            return
        }
        let displayID = screen.displayID
        let shownSection = isShowingAlwaysHidden ? alwaysHiddenSection : hiddenSection

        Task {
            // Let WindowServer settle the expanded section before checking its presentation mode.
            try? await Task.sleep(for: .milliseconds(50))
            guard
                !Task.isCancelled,
                NSScreen.screenWithActiveMenuBar?.displayID == displayID,
                let shownSection
            else {
                return
            }

            switch shownSection.presentationMode(on: screen) {
            case .inline:
                break
            case .inlineHidingApplicationMenus, .thawBar:
                self.hideApplicationMenus()
            }
        }
    }

    // MARK: - Average Color

    /// Average tint uses the bar strip; gradient tint also needs a full-height wallpaper palette.
    /// Track both so observers detect adaptive-kind changes and retries know when capture is complete.
    nonisolated struct AdaptiveCaptureRequirements: Equatable {
        /// Whether the average color of the menu bar strip is needed.
        let needsAverageColor: Bool

        /// Whether a palette of the wallpaper's dominant colors is needed.
        let needsPalette: Bool

        /// Whether the configuration samples the wallpaper at all.
        var isAdaptive: Bool {
            needsAverageColor || needsPalette
        }

        init(configuration: MenuBarAppearancePartialConfiguration, thawBarConfiguration: MenuBarAppearancePartialConfiguration? = nil) {
            let configurations = [configuration] + (thawBarConfiguration.map { [$0] } ?? [])
            needsAverageColor = configurations.contains { $0.backgroundKind == .adaptive || $0.tintKind.isAdaptive }
            needsPalette = configurations.contains { $0.tintKind == .adaptiveGradient }
        }
    }

    nonisolated enum AdaptiveRefreshAction: Equatable {
        /// Sampling requirements did not change.
        case unchanged

        /// Start the refresh: capture, then poll and watch the wallpaper.
        case start

        /// Capture changed requirements without restarting the running refresh.
        case recapture

        case stop
    }

    static nonisolated func adaptiveRefreshAction(
        from previous: AdaptiveCaptureRequirements?,
        to current: AdaptiveCaptureRequirements
    ) -> AdaptiveRefreshAction {
        guard previous != current else { return .unchanged }
        guard current.isAdaptive else {
            // Stop even on the first configuration so an earlier observer's refresh cannot outlive it.
            return .stop
        }
        return previous?.isAdaptive == true ? .recapture : .start
    }

    /// Fire-and-forget refresh; callers needing fresh state immediately must await updateAverageColorInfoAsync.
    func updateAverageColorInfo() {
        Task { [weak self] in
            await self?.updateAverageColorInfoAsync()
        }
    }

    /// Awaitable refresh; color writes finish on MainActor before returning.
    func updateAverageColorInfoAsync(for requestedDisplayID: CGDirectDisplayID? = nil) async {
        guard let appState, appState.navigationState.hasVisibleCaptureUI else { return }

        let isSettingsVisible = settingsWindow?.isVisible == true
        let requirements = adaptiveCaptureRequirements
        let isAdaptiveActive = requirements?.isAdaptive ?? false

        let targetScreens: [NSScreen]
        if let requestedDisplayID {
            guard let screen = NSScreen.screen(for: requestedDisplayID) else { return }
            targetScreens = [screen]
        } else if isAdaptiveActive {
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

        let needsPalette = requirements?.needsPalette ?? false

        // Prevent slow captures from overwriting newer colors.
        captureGeneration += 1
        let generation = captureGeneration

        // Capture serially so a newer generation can take over between displays.
        for screen in targetScreens {
            let displayID = screen.displayID
            // Stop if a newer pass has taken over.
            guard captureGeneration == generation else { break }
            guard let result = await captureAverageColor(
                for: displayID,
                from: windows,
                needsPalette: needsPalette
            )
            else {
                continue
            }
            // Recheck after suspension before publishing over a newer pass.
            guard captureGeneration == generation else { break }
            let (_, info, paletteCapture) = result
            if averageColors[displayID] != info {
                averageColors[displayID] = info
            }
            if displayID == activeDisplayID, averageColorInfo != info {
                averageColorInfo = info
            }
            if let paletteCapture {
                publish(paletteCapture, for: displayID)
            }
        }
    }

    /// A palette with the inputs it was captured from.
    private struct PaletteCapture {
        let palette: WallpaperPalette
        let state: PaletteRefreshState
    }

    private struct PaletteRefreshState {
        let source: WallpaperPaletteRefreshPolicy.Source
        let refreshedAt: ContinuousClock.Instant
    }

    /// Record the inputs only with the palette they produced, so a superseded pass cannot mark a stale palette fresh.
    private func publish(_ capture: PaletteCapture, for displayID: CGDirectDisplayID) {
        if wallpaperPalettes[displayID] != capture.palette {
            wallpaperPalettes[displayID] = capture.palette
        }
        paletteRefreshStates[displayID] = capture.state
    }

    /// Each sample holds a capture ticket because this sampler can run without a surface opening the ordinary gate.
    private func captureAverageColor(
        for displayID: CGDirectDisplayID,
        from windows: [WindowInfo],
        needsPalette: Bool
    ) async -> (CGDirectDisplayID, MenuBarAverageColorInfo, PaletteCapture?)? {
        guard let sample = await ScreenCapture.withOneshotCaptureTicket({
            await MenuBarColorSampler.captureStrip(for: displayID, from: windows)
        }),
            let color = sample.image.averageColor(option: .ignoreAlpha)
        else {
            return nil
        }
        var paletteCapture: PaletteCapture?
        if needsPalette {
            paletteCapture = await capturePaletteIfStale(for: displayID, sample: sample, stripColor: color)
        }
        return (displayID, MenuBarAverageColorInfo(color: color, source: .menuBarWindow), paletteCapture)
    }

    /// Strip samples arrive every few seconds; the full-wallpaper capture runs only when the policy finds the palette stale.
    private func capturePaletteIfStale(
        for displayID: CGDirectDisplayID,
        sample: MenuBarColorSampler.Sample,
        stripColor: CGColor
    ) async -> PaletteCapture? {
        let source = WallpaperPaletteRefreshPolicy.Source(
            wallpaperGeneration: wallpaperGeneration,
            stripColor: stripColor,
            wallpaperBounds: sample.wallpaperBounds,
            isDarkAppearance: SystemAppearance.current == .dark
        )
        let now = ContinuousClock.now
        // A display without a usable palette has nothing to reuse, whatever was recorded for it.
        let state = wallpaperPalettes[displayID]?.primary == nil ? nil : paletteRefreshStates[displayID]
        let reason = WallpaperPaletteRefreshPolicy.refreshReason(
            previous: state?.source,
            current: source,
            timeSinceLastRefresh: state.map { now - $0.refreshedAt },
            fallbackInterval: Self.paletteFallbackInterval
        )
        guard let reason else { return nil }
        diagLog.debug("Refreshing wallpaper palette for display \(displayID): \(reason)")

        // The one-pixel strip suffices for averaging, but a palette needs the wallpaper's full height.
        let palette = await ScreenCapture.withOneshotCaptureTicket {
            await ScreenCapture.captureWindows(
                with: sample.windowIDs,
                screenBounds: sample.wallpaperBounds,
                option: .nominalResolution
            )
        }?.dominantColors()
        // Retain the previous palette on misses or empty swatches to avoid losing tint or falling back to average color.
        guard let palette, palette.primary != nil else { return nil }
        return PaletteCapture(palette: palette, state: PaletteRefreshState(source: source, refreshedAt: now))
    }

    /// Retry early WindowServer capture failures until all screens have the required samples or the budget expires.
    private func captureAdaptiveColorWithRetry() {
        // Await capture to avoid spending retries on stale reads.
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

    /// Palette capture can fail while the strip succeeds; require both when needed so retries do not stop on the fallback.
    private func hasCompleteAdaptiveCapture() -> Bool {
        // No capture requirements means further retries would only spin.
        guard let requirements = adaptiveCaptureRequirements else { return true }
        return NSScreen.managedScreens.allSatisfy { screen in
            let displayID = screen.displayID
            guard averageColors.keys.contains(displayID) else { return false }
            return !requirements.needsPalette || wallpaperPalettes[displayID]?.primary != nil
        }
    }

    // MARK: - Context Menu

    /// Right-click menu for Thaw controls.
    /// - Parameter point: Where to place the menu, in screen coordinates.
    func showSecondaryContextMenu(at point: CGPoint) {
        let menu = NSMenu(title: "\(Constants.displayName)")

        // Reserve symbols for common actions, file locations, or devices; both editors qualify.
        // ControlItemMenuController uses the same rule for left-click menus.
        let editAppearanceItem = contextMenuItem(
            title: String(localized: "Edit Appearance…"),
            action: #selector(showAppearanceEditorPanel),
            symbolName: "swatchpalette",
            accessibilityDescription: "Edit Appearance"
        )
        menu.addItem(editAppearanceItem)

        let editLayoutItem = contextMenuItem(
            title: String(localized: "Edit Layout…"),
            action: #selector(showLayoutEditorPanel),
            symbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "Edit Layout"
        )
        menu.addItem(editLayoutItem)

        if let profilesItem = makeProfilesMenuItem() {
            menu.addItem(.separator())
            menu.addItem(profilesItem)
        }

        menu.addItem(.separator())

        // Standard lifecycle actions stay text-only, matching native menus.
        // Leave Settings untargeted so the responder chain reaches the app delegate.
        let settingsItem = contextMenuItem(
            title: String(localized: "Settings…"),
            action: #selector(AppDelegate.openSettingsWindow),
            accessibilityDescription: "Settings",
            keyEquivalent: ",",
            targetsSelf: false
        )
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = contextMenuItem(
            title: String(localized: "Quit \(Constants.displayName)"),
            action: #selector(quitFromSecondaryContextMenu),
            accessibilityDescription: "Quit",
            keyEquivalent: "q",
            modifiers: .command
        )
        menu.addItem(quitItem)

        // Option replaces Quit with Restart using the same key equivalent.
        let restartItem = contextMenuItem(
            title: String(localized: "Restart \(Constants.displayName)"),
            action: #selector(restartFromSecondaryContextMenu),
            accessibilityDescription: "Restart",
            keyEquivalent: "q",
            modifiers: [.command, .option]
        )
        restartItem.isAlternate = true
        menu.addItem(restartItem)

        menu.popUp(positioning: nil, at: point, in: nil)
    }

    /// Defaults to this manager; use targetsSelf: false for responder-chain actions.
    /// Symbols are optional because most menu items should stay text-only.
    private func contextMenuItem(
        title: String,
        action: Selector,
        symbolName: String? = nil,
        accessibilityDescription: String,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags? = nil,
        targetsSelf: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        if let modifiers {
            item.keyEquivalentModifierMask = modifiers
        }
        if targetsSelf {
            item.target = self
        }
        if let symbolName {
            item.setSymbolImage(systemName: symbolName, accessibilityDescription: accessibilityDescription)
        }
        return item
    }

    /// Checks the active profile; returns nil when no profiles exist.
    private func makeProfilesMenuItem() -> NSMenuItem? {
        guard let appState, !appState.profileManager.profiles.isEmpty else {
            return nil
        }

        // Profiles lists named destinations rather than one common action; keep parent and entries text-only.
        let profilesItem = NSMenuItem(
            title: String(localized: "Profiles"),
            action: nil,
            keyEquivalent: ""
        )

        let submenu = NSMenu()
        for metadata in appState.profileManager.profiles {
            let item = NSMenuItem(
                title: metadata.name,
                action: #selector(applyProfileFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = metadata.id
            if metadata.id == appState.profileManager.activeProfileID {
                item.state = .on
            }
            submenu.addItem(item)
        }
        profilesItem.submenu = submenu

        return profilesItem
    }

    @objc private func quitFromSecondaryContextMenu() {
        // popUp tracks in a nested run loop inside a MainActor task; defer termination to default mode after both unwind.
        // This lets the termination wait loop drain applicationShouldTerminate's restore and timeout tasks.
        ApplicationTermination.request()
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
                // The menu is gone; report failure like the Profiles pane so the pick does not appear successful.
                self?.diagLog.error("Failed to apply profile \(profileID): \(error)")
                NSAlert(error: error).runModal()
            }
        }
    }

    // MARK: - Application Menus

    /// AppKit cannot hide another app's menus; activating Thaw as regular replaces them with empty menus and briefly shows it in the Dock.
    /// - Parameter manual: true for URL/hotkey requests, preventing section state from restoring the menus.
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

        Task { @MainActor in
            guard isHidingApplicationMenus else { return }

            appState.activate(withPolicy: .regular)

            // Retry activation after a short delay because the system can ignore the first after a policy change.
            try? await Task.sleep(for: .milliseconds(25))
            guard isHidingApplicationMenus else { return }
            appState.activate()
        }
    }

    /// Return to accessory policy and clear manual ownership of menu hiding.
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

    /// Only users reach this toggle, so hiding here takes manual ownership.
    func toggleApplicationMenus() {
        if isHidingApplicationMenus {
            showApplicationMenus()
        } else {
            hideApplicationMenus(manual: true)
        }
    }

    // MARK: - Zen Mode

    /// Zen keeps concealable sections hidden and locks hover reveal.
    private(set) var isZenModeActive = false

    /// Restore these reveals on zen exit; session-only, never retained across relaunches.
    private var sectionsRevealedBeforeZenMode: Set<MenuBarSection.Name> = []

    /// Locks reveal gestures and conceals sections until toggled back, then restores prior reveals without layout writes.
    /// - Returns: Whether the toggle applied.
    @discardableResult
    func toggleZenMode() -> Bool {
        // Manual ownership outlives automatic presentation or recording requests.
        isZenModeEngagedAutomatically = false
        automaticZenReasons.removeAll()
        if isZenModeActive {
            deactivateZenMode()
        } else {
            activateZenMode()
        }
        return true
    }

    /// Zen stays engaged until the last automatic source clears, so presenting and recording cannot cancel each other.
    enum AutomaticZenReason: Sendable, Hashable {
        /// PresentationMonitor sees mirroring or screen sharing.
        case screenSharing
        /// RecordingWatchManager sees the camera or microphone in use.
        case recording
    }

    /// Only automatic engagements withdraw automatically; ending a recording or presentation cannot cancel manual zen.
    private var isZenModeEngagedAutomatically = false

    /// Withdraw automatic zen only when the last requesting source clears.
    private var automaticZenReasons: Set<AutomaticZenReason> = []

    /// Idempotent because sources reevaluate signals rather than track edges.
    /// Record reasons during manual zen too, but never withdraw a manual engagement.
    func setAutomaticZenMode(_ isActive: Bool, reason: AutomaticZenReason) {
        if isActive {
            automaticZenReasons.insert(reason)
            guard !isZenModeActive else { return }
            activateZenMode()
            isZenModeEngagedAutomatically = true
        } else {
            automaticZenReasons.remove(reason)
            guard isZenModeActive, isZenModeEngagedAutomatically,
                  automaticZenReasons.isEmpty else { return }
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
        // hide() re-enables hover through resetClosedPresentationState; lock only after all hides.
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

    // MARK: - Swap

    /// Persist swap orientation so the button label stays correct across relaunches; see clearSwapState().
    private(set) var isSwapped = Defaults.bool(forKey: .swapActive) {
        didSet {
            guard oldValue != isSwapped else { return }
            Defaults.set(isSwapped, forKey: .swapActive)
        }
    }

    /// UI settling state only; groups already traded places, so this must not block the next swap.
    private(set) var isSwapInFlight = false

    /// Cancel superseded swaps to avoid racing whole-bar applies.
    private var swapTask: Task<Void, Never>?

    /// Swap again from this target, not the partially reordered cache, while convergence is in flight.
    private var swapTargetOrder: [String: [String]]?

    /// Profiles and resets reassign every item and invalidate swap state; single-item edits still allow swapping back.
    func clearSwapState() {
        swapTask?.cancel()
        swapTask = nil
        swapTargetOrder = nil
        isSwapInFlight = false
        isSwapped = false
    }

    /// Trades Visible/Hidden with internal order preserved and Always Hidden untouched; swap again to undo.
    /// Persist via profile layout because MenuBarAgent reseats transiently re-allowed bundles at remembered slots.
    /// - Returns: Whether the swap started; refusals show on screen and accepted swaps announce their outcome.
    @discardableResult
    func toggleSwap() -> Bool {
        guard let appState, sectionController.isOperational else {
            ThawHUD.show(symbol: "arrow.left.arrow.right", text: "Swap isn't ready yet. Try again in a moment.")
            return false
        }
        guard let hidden = section(withName: .hidden), hidden.isEnabled else {
            ThawHUD.show(symbol: "arrow.left.arrow.right", text: "Turn on Hidden to swap")
            return false
        }
        // Profile snapshots preserve closed apps and exclude transient Control Center widgets.
        let snapshot = appState.profileManager.currentLayoutSnapshot(from: appState)
        let hideable = Dictionary(
            appState.itemManager.managedItems.map { ($0.uniqueIdentifier, $0.canBeHidden && !$0.isControlItem) },
            uniquingKeysWith: { first, _ in first }
        )
        // Use the previous target so two quick swaps land where they started.
        // Closed apps lack live items; treat unknown IDs as hideable unless macOS pins them.
        let base = swapTargetOrder ?? snapshot.itemOrder ?? [:]
        let order = Self.transmutedOrder(base) {
            hideable[$0] ?? !MenuBarItemManager.namesPinnedSystemItem($0)
        }
        let visibleKey = MenuBarSectionName.visible.rawValue
        let hiddenKey = MenuBarSectionName.hidden.rawValue
        guard order[visibleKey]?.isEmpty == false || order[hiddenKey]?.isEmpty == false else {
            ThawHUD.show(symbol: "arrow.left.arrow.right", text: "Nothing to swap")
            return false
        }
        var sectionMap = [String: String]()
        for (sectionKey, identifiers) in order {
            for identifier in identifiers {
                sectionMap[identifier] = sectionKey
            }
        }

        // Close reveals so they cannot reconcile against the changing bar.
        for section in sections where !section.isHidden {
            section.hide()
        }

        // Earlier missing-item memory must not shorten this user-requested apply's wait.
        appState.itemManager.forgetMissingRepublishMemory()

        // Apply membership immediately for a responsive button; the slower profile pass only restores each group's order.
        sectionController.applyProfileLayout(itemSectionMap: sectionMap, itemOrder: order)
        swapTask?.cancel()
        swapTargetOrder = order
        isSwapped.toggle()
        ThawHUD.show(
            symbol: isSwapped ? "arrow.left.arrow.right.circle.fill" : "arrow.left.arrow.right.circle",
            text: isSwapped ? "Swapped" : "Swapped back"
        )

        isSwapInFlight = true
        swapTask = Task { @MainActor [weak self, weak appState] in
            defer {
                if !Task.isCancelled {
                    self?.isSwapInFlight = false
                    self?.swapTargetOrder = nil
                }
            }
            guard let appState else { return }
            let applied = await appState.itemManager.applyProfileLayout(
                pinnedHidden: Set(snapshot.pinnedHiddenBundleIDs),
                pinnedAlwaysHidden: Set(snapshot.pinnedAlwaysHiddenBundleIDs),
                sectionOrder: order,
                itemSectionMap: sectionMap,
                itemOrder: order
            )
            guard let self, !Task.isCancelled else { return }
            guard applied else {
                ThawHUD.show(symbol: "exclamationmark.triangle", text: "Couldn’t finish reordering")
                return
            }
            // Converge only if the profile pass stalled; an already-matching bar needs no second animated reflow.
            let liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            let visibleOrder = order[MenuBarSectionName.visible.rawValue] ?? []
            if appState.itemManager.liveOrderMatches(
                visibleOrder,
                section: .visible,
                controller: self.sectionController,
                items: liveItems
            ) {
                self.diagLog.debug("swap: visible order already realized; skipping the converging apply")
            } else {
                appState.itemManager.scheduleSectionOrderApply(for: .visible)
            }
        }
        return true
    }

    /// Preserve each group's sequence; unhideable items stay after the arriving Visible group because macOS pins them right.
    static nonisolated func transmutedOrder(
        _ order: [String: [String]],
        canHide: (String) -> Bool
    ) -> [String: [String]] {
        let visibleKey = MenuBarSectionName.visible.rawValue
        let hiddenKey = MenuBarSectionName.hidden.rawValue
        let visible = order[visibleKey] ?? []
        let hidden = order[hiddenKey] ?? []
        var result = order
        result[visibleKey] = hidden + visible.filter { !canHide($0) }
        result[hiddenKey] = visible.filter(canHide)
        return result
    }

    // MARK: - Editor Panels

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

    func dismissAppearanceEditorPanel() {
        appearanceEditorPanel.close()
    }

    // MARK: - Sections

    /// A new reveal cancels pending focus rehide.
    func updateLastShowTimestamp() {
        lastShowTimestamp = .now
        focusChangeRehideTask?.cancel()
    }

    /// Updates the control item states for all sections.
    ///
    /// - Parameter screen: The screen to use for the update. If nil, the
    ///   best screen is determined automatically.
    func updateControlItemStates(for screen: NSScreen? = nil) {
        for section in sections {
            section.updateControlItemState(for: screen)
        }
    }

    /// Apply per-display "Always show hidden items" through assignments; divider updates alone cannot reveal items.
    private func synchronizeAlwaysShowHiddenItems() {
        guard let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main else {
            return
        }

        let settings = appState?.settings.displaySettings
        let shouldAlwaysShow = settings?.alwaysShowHiddenItems(for: screen.displayID) == true
            && !shouldUseThawBar(for: screen.displayID)

        if shouldAlwaysShow {
            if sectionController.revealedSection == nil {
                sectionController.show(.alwaysHidden)
            }
            isAlwaysShowRevealActive = true
        } else if isAlwaysShowRevealActive {
            sectionController.hideRevealedSections()
            isAlwaysShowRevealActive = false
        }
    }

    /// Every section name is present; the optional supports caller chaining.
    func section(withName name: MenuBarSection.Name) -> MenuBarSection? {
        sections.first { $0.name == name }
    }

    func controlItem(withName name: MenuBarSection.Name) -> ControlItem? {
        section(withName: name)?.controlItem
    }

    /// Capture cleanup consults this timestamp so it cannot undo a newer user reveal.
    @ObservationIgnored
    private(set) var lastUserRevealDate: Date?

    func noteUserRevealOwnership() {
        lastUserRevealDate = Date()
    }

    /// Distinguish in-flight reveal reflow from a section simply left open.
    private func observeRevealTransitions(into bag: inout Set<AnyCancellable>) {
        revealedSectionChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.lastRevealTransition = .now
            }
            .store(in: &bag)
    }

    /// Whether a reveal or hide is still reflowing the bar.
    var isRevealReflowSettling: Bool {
        guard let lastRevealTransition else {
            return false
        }
        return Date.now.timeIntervalSince(lastRevealTransition) < Self.revealReflowSettleWindow
    }

    /// The kit suppresses nudges during assertion recompositing, which already lays out the bar; extra resizing flickers.
    /// It clears this before position-restoring writes; isRevealReflowSettling guards new transitions during suspended restores.
    @ObservationIgnored
    private var revealHideTransitionActive = false

    /// Exposed for the nudge gate.
    var isRevealHideTransitionActive: Bool {
        revealHideTransitionActive
    }

    func setRevealHideTransitionActive(_ active: Bool) {
        revealHideTransitionActive = active
        // Either edge of the transition moves the items, so the pill should follow closely.
        leadingEdgeWatcher.expectChange()
    }

    /// Suppress width nudges and structural normalization during the transition or fixed settling window.
    var shouldSuppressMenuBarAgentNudge: Bool {
        isRevealReflowSettling || revealHideTransitionActive
    }

    /// Cursor-free invalidation after position writes; suppress during reflow to avoid missed rehide clicks, but allow settled reveals.
    /// Returns whether armed, not evidence about MenuBarAgent when skipped; see ControlItem.requestMenuBarAgentPositionRefresh.
    @discardableResult
    func requestMenuBarAgentPositionRefresh() -> Bool {
        guard !shouldSuppressMenuBarAgentNudge else {
            diagLog.debug(
                "Skipping MenuBarAgent position refresh: reveal/hide transition or reflow still settling"
            )
            return false
        }
        return controlItem(withName: .visible)?.requestMenuBarAgentPositionRefresh() ?? false
    }

    /// Remove controls before termination to avoid ghost icons; see ControlItem.tearDownForTermination.
    func tearDownControlItemsForTermination() {
        for section in sections {
            section.controlItem.tearDownForTermination()
        }
    }

    // MARK: - Per-Item Hotkeys

    /// Reconcile incrementally at setup, cache changes, and profile apply to preserve in-use registrations.
    /// Retain saved bindings for quit apps; drop only identifiers neither present nor configured.
    func rebuildItemHotkeys() {
        guard let appState else { return }

        let saved = Defaults.dictionary(forKey: .menuBarItemHotkeys) as? [String: Data] ?? [:]
        let dec = JSONDecoder()
        let enc = JSONEncoder()

        // Assign only actionable items with a resolved source; unresolved apps use unstable UUIDs.
        // Always retain saved bindings so filtering present items cannot strand recorded hotkeys.
        let presentIdentifiers = Set(
            appState.itemManager.managedItems
                .filter { $0.isUserActionable && $0.sourcePID != nil }
                .map(\.uniqueIdentifier)
        )
        let wantedIdentifiers = presentIdentifiers.union(saved.keys)

        var newHotkeys = itemHotkeys

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
                // Assign only changed bindings to avoid redundant persistence writes.
                if existing.keyCombination != savedCombo {
                    existing.keyCombination = savedCombo
                }
                continue
            }

            let hotkey = Hotkey(action: .openMenuBarItem)
            hotkey.performSetup(with: appState)
            hotkey.keyCombination = savedCombo
            hotkeyItemMap[ObjectIdentifier(hotkey)] = identifier

            // Install persistence after the initial value so restoring a binding does not write it back.
            hotkey.keyCombinationDidChange = { [weak self, weak hotkey] in
                guard let self, let hotkey else { return }
                let newCombo = hotkey.keyCombination
                var dict = Defaults.dictionary(forKey: .menuBarItemHotkeys) as? [String: Data] ?? [:]
                if let combo = newCombo, let data = try? enc.encode(combo) {
                    dict[identifier] = data
                } else {
                    dict.removeValue(forKey: identifier)
                }
                Defaults.set(dict, forKey: .menuBarItemHotkeys)
                hotkeyItemMap[ObjectIdentifier(hotkey)] = newCombo != nil ? identifier : nil
            }

            newHotkeys[identifier] = hotkey
        }

        itemHotkeys = newHotkeys
    }

    /// Resolve from the cache and use shared activation; absent items, such as quit apps, are a no-op.
    func openItem(withIdentifier identifier: String) {
        guard let appState else { return }
        guard let item = appState.itemManager.managedItems.first(
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

/// A color sample and its source, kept as a Hashable value so equality determines whether repainting is needed.
struct MenuBarAverageColorInfo: Hashable {
    /// Where a sample was measured. The menu bar window itself is preferred;
    /// the desktop picture stands in when that window cannot be read.
    enum Source: Hashable {
        case menuBarWindow
        case desktopWallpaper
    }

    var color: CGColor

    var source: Source

    /// WCAG relative luminance (0...1) for contrast floors; returns 0 if the color cannot convert to sRGB.
    var relativeLuminance: Double {
        ForegroundContrast.relativeLuminance(of: color) ?? 0
    }

    /// A separate notch threshold allows darker foreground beside the notch, where content reads lighter.
    /// Both thresholds use the contrast crossover to avoid weakening either polarity.
    /// - Parameter screen: Screen to judge for; nil uses the screen currently owning the menu bar.
    /// - Returns: true if the background calls for dark foreground content.
    func isBright(for screen: NSScreen?) -> Bool {
        let subject = screen ?? NSScreen.screenWithActiveMenuBar
        let threshold = subject?.hasNotch == true
            ? Constants.notchedDisplayBrightnessThreshold
            : Constants.menuBarBrightnessThreshold
        return relativeLuminance > threshold
    }

    /// Judge the tinted background, not the raw sample: even 20% black over #808080 changes the preferred polarity.
    /// - Parameters:
    ///   - tint: The tint color painted over the sample.
    ///   - opacity: Opacity the tint is painted at, from 0 to 1.
    /// - Returns: The composited sample, or self if tint cannot convert to sRGB.
    func tinted(by tint: CGColor, opacity: Double) -> MenuBarAverageColorInfo {
        guard let composited = ForegroundContrast.composited(tint, over: color, opacity: opacity) else {
            return self
        }
        return MenuBarAverageColorInfo(color: composited, source: source)
    }
}

private extension MenuBarGroupMoveRefusal {
    /// One-to-one mapping keeps PlatformRuntimeKit types out of the layout bar.
    init(_ refusal: RuntimeGroupMoveRefusal) {
        self = switch refusal {
        case let .protectedMember(item): .protectedMember(item: item)
        case let .hidingUnsupported(item): .hidingUnsupported(item: item)
        case let .notHideable(item): .notHideable(item: item)
        case .hidingUnavailable: .hidingUnavailable
        case let .unresolvedMembers(missingCount): .unresolvedMembers(missingCount: missingCount)
        }
    }
}
