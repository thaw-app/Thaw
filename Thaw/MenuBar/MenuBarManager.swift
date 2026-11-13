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
import ThawUI

/// Owns sections, panels, per-item hotkeys, and color samples, reacting to system and setting changes after setup.
/// AppState owns this manager; methods stop when the weak back reference is gone.
@MainActor
@Observable
final class MenuBarManager {
    /// Samples the bar and wallpaper colours for adaptive appearances and the settings preview.
    let wallpaperColorMonitor = MenuBarWallpaperColorMonitor()

    /// Information for the menu bar's average color on the active screen.
    var averageColorInfo: MenuBarAverageColorInfo? {
        wallpaperColorMonitor.averageColorInfo
    }

    /// Per-screen average colors for multi-monitor adaptive backgrounds.
    var averageColors: [CGDirectDisplayID: MenuBarAverageColorInfo] {
        wallpaperColorMonitor.averageColors
    }

    /// Per-screen dominant-color palettes for the adaptive gradient tint.
    var wallpaperPalettes: [CGDirectDisplayID: WallpaperPalette] {
        wallpaperColorMonitor.wallpaperPalettes
    }

    /// Awaitable colour refresh; see MenuBarWallpaperColorMonitor.updateAverageColorInfoAsync.
    func updateAverageColorInfoAsync(for requestedDisplayID: CGDirectDisplayID? = nil) async {
        await wallpaperColorMonitor.updateAverageColorInfoAsync(for: requestedDisplayID)
    }

    /// Hides the front app's menus when a revealed section needs their room or the user asks.
    let applicationMenuHider = ApplicationMenuHider()

    /// System hiding or auto-hiding, independent of Thaw's concealment.
    private(set) var isMenuBarHiddenBySystem = false

    /// Persisted _HIHideMenuBar value, unlike isMenuBarHiddenBySystem which also reflects transient app presentation options.
    private(set) var isMenuBarHiddenBySystemUserDefaults = false

    /// Pause hover after an explicit toggle so it cannot undo the user; it resumes once the pointer leaves the hover band.
    var showOnHoverAllowed = true {
        didSet {
            // Hiding a section and the hover rearm both allow hover again, which undid Zen Mode's lock.
            if showOnHoverAllowed, isZenModeActive {
                showOnHoverAllowed = false
                return
            }
            guard oldValue != showOnHoverAllowed else { return }
            diagLog.debug("hover: \(showOnHoverAllowed ? "allowed again" : "paused")")
        }
    }

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

    /// Built at setup; owns the rehides that focus changes and outside clicks arm.
    @ObservationIgnored
    private(set) var rehideController: RehideController?

    /// Menu-opening hotkeys keyed by uniqueIdentifier, mirroring ProfileManager's per-profile bindings.
    private(set) var itemHotkeys: [String: Hotkey] = [:]

    /// Reverse map from a hotkey instance to the item identifier it opens.
    /// Read by Hotkey.Listener when an openMenuBarItem hotkey fires.
    var hotkeyItemMap: [ObjectIdentifier: String] = [:]

    /// Keyed by identifier so one binding's persistence observer can be removed independently.
    @ObservationIgnored
    private var itemHotkeyCancellables = [String: AnyCancellable]()

    let thawBarPanel = ThawBarPanel()

    let searchPanel = MenuBarSearchPanel()

    /// Standalone appearance editor for changes without opening Settings.
    let appearanceEditorPanel = MenuBarAppearanceEditorPanel()

    let layoutEditorPanel = MenuBarLayoutEditorPanel()

    /// Non-optional platform controller behind an interface so app callers need no platform type; settable for tests.
    var sectionController: any MenuBarSectionControlling = InertSectionController()

    /// Concrete access for platform-typed operations, exposed to callers only through this manager.
    private(set) var runtimeSectionController: RuntimeSectionController?

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
    let newIconFollower = NewIconSectionFollower()
    /// Who opened the current reveal, so Thaw's own reveals are not counted as the user's.
    let revealAttribution = RevealAttribution()
    /// Holds nudges off during reveal reflow and the kit's transition, not a settled reveal, so hidden moves
    /// retain their cursor-free path. Shared with the item manager.
    @ObservationIgnored let barSettling: BarSettling

    init(barSettling: BarSettling = BarSettling()) {
        self.barSettling = barSettling
    }

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

    /// Covers hidden items that flash while an icon capture reveals them.
    let revealCover = RevealCover()

    /// What the bar is drawn over, for anything that paints over the bar.
    let backdrop = MenuBarBackdrop()

    /// The live left edge of the visible run, for anything drawn against it.
    let leadingEdgeWatcher = MenuBarLeadingEdgeWatcher()

    var alwaysShowHiddenItemsController: AlwaysShowHiddenItemsController?
    /// Re-applies "Always show hidden items" when the active menu bar moves to another display.
    private var activeDisplayWatcher: ActiveMenuBarDisplayWatcher?

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
    func shouldUseThawBar(for displayID: CGDirectDisplayID, section: MenuBarSection.Name = .hidden) -> Bool {
        return appState?.settings.displaySettings.useThawBar(for: displayID, section: section) == true
            || sectionController.isNativeOverflowActive(on: displayID) == true
            || MenuBarSection.forcesThawBarForNotchOverflow(
                overflowEnabled: configuration.enableMenuBarItemOverflow,
                useThawBarOnOverflow: appState?.settings.thawBar.useThawBarOnNotchOverflow ?? true,
                hasEjectedItems: !sectionController.overflowHiddenIdentifiers.isEmpty
            )
    }

    // MARK: - Setup

    func performSetup(with appState: AppState, activeDisplayWatcher: ActiveMenuBarDisplayWatcher, displays: DisplayEnvironment) {
        self.appState = appState
        wallpaperColorMonitor.performSetup(with: appState)
        applicationMenuHider.performSetup(with: appState)
        self.activeDisplayWatcher = activeDisplayWatcher
        configuration = appState.settings
        rehideController = RehideController(environment: .live(appState: appState))
        installObservers()
        thawBarPanel.performSetup(with: appState, displayInvalidations: displays.invalidations, displaySettlements: displays.settlements)
        searchPanel.performSetup(with: appState, displayInvalidations: displays.invalidations)
        appearanceEditorPanel.performSetup(with: appState)
        layoutEditorPanel.performSetup(with: appState, displayInvalidations: displays.invalidations)
        for section in sections {
            section.performSetup(with: appState, displays: displays)
        }
        // Divider reflow cannot hide items; a separate assignment model drives the restriction set.
        nativeAppHidingExperiment.recoverPreviousSession()
        systemExtraTakeover.recoverPreviousSession()
        // Recovery and overflow need notch coverage kept current across display changes.
        MenuBarNotchGeometry.refresh()
        let controller = RuntimeSectionController(
            context: RuntimeSectionContextAdapter(appState: appState, revealAttribution: revealAttribution)
        )
        controller.start()
        sectionController = controller
        runtimeSectionController = controller
        revealAttribution.observe(revealedSectionChanges)
        nativeAppHidingExperiment.start(controller: controller, settings: appState.settings.layout)
        systemExtraTakeover.start(controller: controller, settings: appState.settings.layout) { [weak appState] identifier in
            guard let itemManager = appState?.itemManager,
                  itemManager.knownItemIdentifiers.insert(identifier).inserted
            else {
                return
            }
            itemManager.persistKnownItemIdentifiers()
        }
        newIconFollower.start(appState: appState)
        MenuBarPresentationProvider.startDiagnosticSessionIfGated()
        leadingEdgeWatcher.performSetup(with: appState)
        revealCover.performSetup(with: appState)
        synchronizeAlwaysShowHiddenItems()
        rebuildItemHotkeys()
    }

    // MARK: - Observers

    /// Replace the observer bag as a complete set so rebuilds do not leave partial subscriptions.
    private func installObservers() {
        wallpaperColorMonitor.stopSettingsPreviewRefresh()

        var bag = Set<AnyCancellable>()
        observeSystemMenuBarPresentation(into: &bag)
        observeSystemAutohideDefault(into: &bag)
        observeFocusChangeRehide(into: &bag)
        wallpaperColorMonitor.observeSettingsWindowReference(into: &bag)
        observeUserSettings(into: &bag)
        wallpaperColorMonitor.observeSamplingTriggers(into: &bag)
        applicationMenuHider.observeSectionStates(of: sections, into: &bag)
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
                    barSettling.note(.nativeBarChanged)
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
                self?.rehideController?.note(.focusChanged)
            }
            .store(in: &bag)
    }

    private func observeUserSettings(into bag: inout Set<AnyCancellable>) {
        guard let appState else {
            return
        }

        alwaysShowHiddenItemsController = AlwaysShowHiddenItemsController(
            alwaysShow: appState.settings.displaySettings.alwaysShowHiddenItems,
            usesThawBar: { [weak self] in self?.shouldUseThawBar(for: $0) ?? true },
            isZenModeActive: { [weak self] in self?.isZenModeActive == true },
            revealedSection: { [weak self] in self?.sectionController.revealedSection },
            reveal: { [weak self] in self?.presentAlwaysShowTarget($0) },
            resetPresentation: { [weak self] in
                guard let self else { return }
                showOnHoverAllowed = true
                for section in sections {
                    section.desiredState = .hideSection
                }
            }
        )
        alwaysShowHiddenItemsController?.observeDisplaySettings { [settings = appState.settings.displaySettings] in
            settings.alwaysShowInputs
        } refreshControls: { [weak self] in
            self?.updateControlItemStates()
        }
        activeDisplayWatcher?.isNeeded = { [settings = appState.settings.displaySettings] in
            settings.isAlwaysShowEnabledOnAnyDisplay
        }
        activeDisplayWatcher?.onChange = { [weak self] in
            self?.synchronizeAlwaysShowHiddenItems()
            self?.updateControlItemStates()
        }
        activeDisplayWatcher?.start()

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
        guard let appState, appState.profilesFeature.isOn, !appState.profileManager.profiles.isEmpty else {
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
                try appState.profileManager.switchToProfile(id: profileID, on: appState)
            } catch {
                // The menu is gone; report failure like the Profiles pane so the pick does not appear successful.
                self?.diagLog.error("Failed to apply profile \(profileID): \(error)")
                NSAlert(error: error).runModal()
            }
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
            }
        }
        sectionsRevealedBeforeZenMode = revealedNames
        isZenModeActive = true
        // Snapshot both sections before the first hide conceals them together.
        for name in revealedNames {
            section(withName: name)?.hide()
        }
        showOnHoverAllowed = false
    }

    private func deactivateZenMode() {
        isZenModeActive = false
        showOnHoverAllowed = true
        if alwaysShowHiddenItemsController?.shouldRestorePreZenReveals == false {
            sectionsRevealedBeforeZenMode = []
        }
        for name in sectionsRevealedBeforeZenMode {
            revealAttribution.policy { section(withName: name)?.show() }
        }
        sectionsRevealedBeforeZenMode = []
        synchronizeAlwaysShowHiddenItems()
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
            hideable[$0] ?? !MoveTargeting.namesPinnedSystemItem($0)
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

    /// Updates the control item states for all sections.
    ///
    /// - Parameter screen: The screen to use for the update. If nil, the
    ///   best screen is determined automatically.
    func updateControlItemStates(for screen: NSScreen? = nil) {
        for section in sections {
            section.updateControlItemState(for: screen)
        }
    }

    var shouldAlwaysShowHiddenItems: Bool {
        alwaysShowHiddenItemsController?.isEnabled == true
    }

    func synchronizeAlwaysShowHiddenItems(closingSections: Bool = false) {
        alwaysShowHiddenItemsController?.synchronize(closingSections: closingSections)
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

    /// The kit suppresses nudges during assertion recompositing, which already lays out the bar; extra resizing flickers.
    /// It clears this before position-restoring writes; the reveal reflow window guards new transitions during suspended restores.
    func setRevealHideTransitionActive(_ active: Bool) {
        barSettling.note(.revealTransition(active: active))
        // Either edge moves the items, so the pill follows closely; at the end it gets the reading it held back.
        leadingEdgeWatcher.expectChange(resending: !active)
    }

    /// Cursor-free invalidation after position writes; suppress during reflow to avoid missed rehide clicks, but allow settled reveals.
    /// Returns whether armed, not evidence about MenuBarAgent when skipped; see ControlItem.requestMenuBarAgentPositionRefresh.
    @discardableResult
    func requestMenuBarAgentPositionRefresh() -> Bool {
        guard barSettling.hold(for: .agentNudge) == nil else {
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

        let store = HotkeyBindingStore.items
        let saved = store.rawBindings()

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
                try? HotkeyBindingStore.combination(from: data)
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
                try? store.set(newCombo, for: identifier)
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
