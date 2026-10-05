//
//  AdvancedSettings.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import MenuBarModel
import Observation
import SwiftUI

/// Model for the app's Advanced settings.
@MainActor
@Observable
final class AdvancedSettings {
    var enableAlwaysHiddenSection = Defaults.DefaultValue.enableAlwaysHiddenSection {
        didSet {
            guard oldValue != enableAlwaysHiddenSection else { return }
            Defaults.set(enableAlwaysHiddenSection, forKey: .enableAlwaysHiddenSection)
        }
    }

    /// The effective state of the always-hidden section. Route behavior through
    /// this, not the raw enableAlwaysHiddenSection.
    var isAlwaysHiddenSectionEnabled: Bool {
        enableAlwaysHiddenSection
    }

    var showAllSectionsOnUserDrag = Defaults.DefaultValue.showAllSectionsOnUserDrag {
        didSet {
            guard oldValue != showAllSectionsOnUserDrag else { return }
            Defaults.set(showAllSectionsOnUserDrag, forKey: .showAllSectionsOnUserDrag)
        }
    }

    var sectionDividerStyle = Defaults.DefaultValue.sectionDividerStyle {
        didSet {
            guard oldValue != sectionDividerStyle else { return }
            Defaults.set(sectionDividerStyle.rawValue, forKey: .sectionDividerStyle)
        }
    }

    /// Manual arrangement disables moves and position-table writes, but keeps hiding and revealing.
    var menuBarArrangementMode = Defaults.DefaultValue.menuBarArrangementMode {
        didSet {
            guard oldValue != menuBarArrangementMode else { return }
            Defaults.set(menuBarArrangementMode.rawValue, forKey: .menuBarArrangementMode)
            if menuBarArrangementMode == .manual {
                // Manual membership follows where items already sit in the bar.
                appState?.itemManager.scheduleObservedMembershipAdoption(reason: "switched to Manual")
            }
        }
    }

    /// Hide application menus when needed to fit menu bar items.
    var hideApplicationMenus = Defaults.DefaultValue.hideApplicationMenus {
        didSet {
            guard oldValue != hideApplicationMenus else { return }
            Defaults.set(hideApplicationMenus, forKey: .hideApplicationMenus)
        }
    }

    var enableSecondaryContextMenu = Defaults.DefaultValue.enableSecondaryContextMenu {
        didSet {
            guard oldValue != enableSecondaryContextMenu else { return }
            Defaults.set(enableSecondaryContextMenu, forKey: .enableSecondaryContextMenu)
        }
    }

    var showOnHoverDelay = Defaults.DefaultValue.showOnHoverDelay {
        didSet {
            guard oldValue != showOnHoverDelay else { return }
            Defaults.set(showOnHoverDelay, forKey: .showOnHoverDelay)
        }
    }

    var tooltipDelay = Defaults.DefaultValue.tooltipDelay {
        didSet {
            guard oldValue != tooltipDelay else { return }
            Defaults.set(tooltipDelay, forKey: .tooltipDelay)
        }
    }

    /// Enables tooltips in the actual menu bar, not just panels and settings.
    var showMenuBarTooltips = Defaults.DefaultValue.showMenuBarTooltips {
        didSet {
            guard oldValue != showMenuBarTooltips else { return }
            Defaults.set(showMenuBarTooltips, forKey: .showMenuBarTooltips)
        }
    }

    /// The interval between icon image refreshes in panels (Thaw Bar, search, layout).
    var iconRefreshInterval = Defaults.DefaultValue.iconRefreshInterval {
        didSet {
            guard oldValue != iconRefreshInterval else { return }
            Defaults.set(iconRefreshInterval, forKey: .iconRefreshInterval)
        }
    }

    /// Limits repeat reveals so animated icons cannot bounce items in and out of the bar.
    /// The watcher reads this each capture batch, so changes need no restart.
    var menuBarItemAlertRevealCooldown = Defaults.DefaultValue.menuBarItemAlertRevealCooldown {
        didSet {
            guard oldValue != menuBarItemAlertRevealCooldown else { return }
            Defaults.set(menuBarItemAlertRevealCooldown, forKey: .menuBarItemAlertRevealCooldown)
        }
    }

    /// Automatic zen mode for mirroring or sharing; see PresentationMonitor for detection limits.
    var autoZenWhileSharingScreen = Defaults.DefaultValue.autoZenWhileSharingScreen {
        didSet {
            guard oldValue != autoZenWhileSharingScreen else { return }
            Defaults.set(autoZenWhileSharingScreen, forKey: .autoZenWhileSharingScreen)
        }
    }

    var enableDiagnosticLogging = Defaults.DefaultValue.enableDiagnosticLogging {
        didSet {
            guard oldValue != enableDiagnosticLogging else { return }
            Defaults.set(enableDiagnosticLogging, forKey: .enableDiagnosticLogging)
            #if DEBUG
                // Keep debug logging enabled despite profile swaps or toggles to retain capture diagnostics.
                DiagnosticLogger.shared.isEnabled = true
            #else
                DiagnosticLogger.shared.isEnabled = enableDiagnosticLogging
            #endif
        }
    }

    /// Move non-fitting Visible items to Hidden only on notched displays.
    /// didSet rebalances only on changes; item-cache updates handle the launch-time pass.
    var enableMenuBarItemOverflow = Defaults.DefaultValue.enableMenuBarItemOverflow {
        didSet {
            guard oldValue != enableMenuBarItemOverflow else { return }
            Defaults.set(enableMenuBarItemOverflow, forKey: .enableMenuBarItemOverflow)
            Task { @MainActor [weak self] in
                guard let itemManager = self?.appState?.itemManager else { return }
                if await itemManager.rebalanceOverflowIfNeeded(reason: .settingChange) {
                    await itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
                }
            }
        }
    }

    /// Readouts show item text below the bar on hover; no reads or drawing while disabled, and no polling without a visible readout.
    var enableMenuBarItemDescenders = Defaults.DefaultValue.enableMenuBarItemDescenders {
        didSet {
            guard oldValue != enableMenuBarItemDescenders else { return }
            Defaults.set(enableMenuBarItemDescenders, forKey: .enableMenuBarItemDescenders)
        }
    }

    var enableSwapBar = Defaults.DefaultValue.enableSwapBar {
        didSet {
            guard oldValue != enableSwapBar else { return }
            Defaults.set(enableSwapBar, forKey: .enableSwapBar)
        }
    }

    /// Whether a plain click on the Thaw icon swaps Visible and Hidden instead
    /// of revealing the hidden section.
    var swapOnThawIconClick = Defaults.DefaultValue.swapOnThawIconClick {
        didSet {
            guard oldValue != swapOnThawIconClick else { return }
            Defaults.set(swapOnThawIconClick, forKey: .swapOnThawIconClick)
        }
    }

    /// Replaces Thaw's status menu with a panel; disabled secondary clicks use NSMenu.
    var enableControlItemPanel = Defaults.DefaultValue.enableControlItemPanel {
        didSet {
            guard oldValue != enableControlItemPanel else { return }
            Defaults.set(enableControlItemPanel, forKey: .enableControlItemPanel)
        }
    }

    var fetchReleaseNotes = Defaults.DefaultValue.fetchReleaseNotes {
        didSet {
            guard oldValue != fetchReleaseNotes else { return }
            Defaults.set(fetchReleaseNotes, forKey: .fetchReleaseNotes)
        }
    }

    /// Opt-in alternative to the assessment assertion. Native app visibility
    /// persists outside Thaw, so the experiment journals and restores its writes.
    var enableNativeAppHiding = Defaults.DefaultValue.enableNativeAppHiding {
        didSet {
            guard oldValue != enableNativeAppHiding else { return }
            if enableNativeAppHiding {
                enableExperimentalSystemItemHiding = false
            }
            Defaults.set(enableNativeAppHiding, forKey: .enableNativeAppHiding)
        }
    }

    /// Movable, hideable stand-ins replace Focus, AirDrop, Now Playing, and Fast User Switching.
    /// macOS hides their originals whenever another item is hidden, even if assigned Visible.
    var enableModuleStandIns = Defaults.DefaultValue.enableModuleStandIns {
        didSet {
            guard oldValue != enableModuleStandIns else { return }
            Defaults.set(enableModuleStandIns, forKey: .enableModuleStandIns)
        }
    }

    /// Replace hidden Time Machine with a stand-in; restore the original on Visible assignment, disable, or quit.
    var enableTimeMachineTakeover = Defaults.DefaultValue.enableTimeMachineTakeover {
        didSet {
            guard oldValue != enableTimeMachineTakeover else { return }
            Defaults.set(enableTimeMachineTakeover, forKey: .enableTimeMachineTakeover)
        }
    }

    /// The Timer counterpart of enableTimeMachineTakeover. Reports itself
    /// unavailable until Timer has a verified switch.
    var enableTimerTakeover = Defaults.DefaultValue.enableTimerTakeover {
        didSet {
            guard oldValue != enableTimerTakeover else { return }
            Defaults.set(enableTimerTakeover, forKey: .enableTimerTakeover)
        }
    }

    /// Removes the Input menu through its own switch and puts a Thaw stand-in
    /// in its place that can be hidden and moved like any item.
    var enableTextInputTakeover = Defaults.DefaultValue.enableTextInputTakeover {
        didSet {
            guard oldValue != enableTextInputTakeover else { return }
            Defaults.set(enableTextInputTakeover, forKey: .enableTextInputTakeover)
        }
    }

    /// Samples camera presence and per-app microphone activity only while enabled.
    var enableRecordingWatch = Defaults.DefaultValue.enableRecordingWatch {
        didSet {
            guard oldValue != enableRecordingWatch else { return }
            Defaults.set(enableRecordingWatch, forKey: .enableRecordingWatch)
        }
    }

    /// Presenter mode: collapse the menu bar to zen mode while the camera or
    /// microphone is in use. Rides the recording watch's detector.
    var zenModeWhileRecording = Defaults.DefaultValue.zenModeWhileRecording {
        didSet {
            guard oldValue != zenModeWhileRecording else { return }
            Defaults.set(zenModeWhileRecording, forKey: .zenModeWhileRecording)
        }
    }

    /// Pointer-following announcements can be pinned for visibility away from the desk.
    /// Resolve each event so changes apply immediately; disconnected targets fall back to the primary display.
    var recordingWatchScreen = Defaults.DefaultValue.recordingWatchScreen {
        didSet {
            guard oldValue != recordingWatchScreen else { return }
            Defaults.set(recordingWatchScreen.storageKey, forKey: .recordingWatchScreen)
        }
    }

    /// Defaults to the shared HUD center, with alternatives to keep announcements out of the work area.
    /// Read per event so placement changes need no relaunch.
    var recordingWatchPlacement = Defaults.DefaultValue.recordingWatchPlacement {
        didSet {
            guard oldValue != recordingWatchPlacement else { return }
            Defaults.set(recordingWatchPlacement.rawValue, forKey: .recordingWatchPlacement)
        }
    }

    /// Cover Finder titles while the desktop is frontmost, leaving the Apple menu and Finder state unchanged.
    /// See ApplicationMenuCover for why this differs from hideApplicationMenus.
    var enableDesktopMenuHiding = Defaults.DefaultValue.enableDesktopMenuHiding {
        didSet {
            guard oldValue != enableDesktopMenuHiding else { return }
            Defaults.set(enableDesktopMenuHiding, forKey: .enableDesktopMenuHiding)
        }
    }

    /// Clock, Control Center, and Siri require the assertion that native hiding releases.
    var enableExperimentalSystemItemHiding = Defaults.DefaultValue.enableExperimentalSystemItemHiding {
        didSet {
            if enableNativeAppHiding, enableExperimentalSystemItemHiding {
                enableExperimentalSystemItemHiding = false
                // A queued URI notification may follow a persisted write, even when the model was already false.
                Defaults.set(false, forKey: .enableExperimentalSystemItemHiding)
                return
            }
            guard oldValue != enableExperimentalSystemItemHiding else { return }
            Defaults.set(enableExperimentalSystemItemHiding, forKey: .enableExperimentalSystemItemHiding)
            appState?.menuBarManager.sectionController.refresh()
        }
    }

    /// Extreme hidden-item weights try to make native overflow collapse them first on macOS 27 notched displays.
    /// Experimental URI/Defaults-only control has no Settings or search entry; see SearchIndex.baseNonSearchableProperties.
    var enableExperimentalOverflowPrevention = Defaults.DefaultValue.enableExperimentalOverflowPrevention {
        didSet {
            guard oldValue != enableExperimentalOverflowPrevention else { return }
            Defaults.set(enableExperimentalOverflowPrevention, forKey: .enableExperimentalOverflowPrevention)
        }
    }

    /// App-icon rendering avoids macOS 27 overflow-control bleed in Thaw Bar and layout captures.
    /// Only affects those previews, not the system menu bar.
    var alwaysUseAppIconForMenuBarItems = Defaults.DefaultValue.alwaysUseAppIconForMenuBarItems {
        didSet {
            guard oldValue != alwaysUseAppIconForMenuBarItems else { return }
            Defaults.set(alwaysUseAppIconForMenuBarItems, forKey: .alwaysUseAppIconForMenuBarItems)
        }
    }

    /// Maximum time to wait for MenuBarAgent to apply a preferred-position
    /// reorder before Thaw continues with residual reconciliation.
    var menuBarOrderFulfillmentTimeout = Defaults.DefaultValue.menuBarOrderFulfillmentTimeout {
        didSet {
            guard oldValue != menuBarOrderFulfillmentTimeout else { return }
            Defaults.set(menuBarOrderFulfillmentTimeout, forKey: .menuBarOrderFulfillmentTimeout)
        }
    }

    /// The order in which menu bar sections appear in the search panel.
    var searchSectionOrder: [MenuBarSection.Name] = Defaults.DefaultValue.searchSectionOrder
        .compactMap(MenuBarSection.Name.init(rawValue:))
    {
        didSet {
            guard oldValue != searchSectionOrder else { return }
            Defaults.set(searchSectionOrder.map(\.rawValue), forKey: .searchSectionOrder)
        }
    }

    var searchIncludeVisible = Defaults.DefaultValue.searchIncludeVisible {
        didSet {
            guard oldValue != searchIncludeVisible else { return }
            Defaults.set(searchIncludeVisible, forKey: .searchIncludeVisible)
        }
    }

    var searchIncludeHidden = Defaults.DefaultValue.searchIncludeHidden {
        didSet {
            guard oldValue != searchIncludeHidden else { return }
            Defaults.set(searchIncludeHidden, forKey: .searchIncludeHidden)
        }
    }

    var searchIncludeAlwaysHidden = Defaults.DefaultValue.searchIncludeAlwaysHidden {
        didSet {
            guard oldValue != searchIncludeAlwaysHidden else { return }
            Defaults.set(searchIncludeAlwaysHidden, forKey: .searchIncludeAlwaysHidden)
        }
    }

    /// Search opens at its saved location, centered, or at the pointer; defaults to inspector.
    /// Read on each opening rather than watched because Settings focus closes the panel.
    var menuBarSearchPresentation = Defaults.DefaultValue.menuBarSearchPresentation {
        didSet {
            guard oldValue != menuBarSearchPresentation else { return }
            Defaults.set(menuBarSearchPresentation.rawValue, forKey: .menuBarSearchPresentation)
        }
    }

    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    @ObservationIgnored
    private(set) weak var appState: AppState?

    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
        configureObservers()
    }

    func loadInitialState() {
        Defaults.ifPresent(key: .enableAlwaysHiddenSection, assign: &enableAlwaysHiddenSection)
        Defaults.ifPresent(key: .showAllSectionsOnUserDrag, assign: &showAllSectionsOnUserDrag)
        Defaults.ifPresent(key: .hideApplicationMenus, assign: &hideApplicationMenus)
        Defaults.ifPresent(key: .enableSecondaryContextMenu, assign: &enableSecondaryContextMenu)
        Defaults.ifPresent(key: .showOnHoverDelay, assign: &showOnHoverDelay)
        Defaults.ifPresent(key: .tooltipDelay, assign: &tooltipDelay)
        Defaults.ifPresent(key: .showMenuBarTooltips, assign: &showMenuBarTooltips)
        Defaults.ifPresent(key: .iconRefreshInterval, assign: &iconRefreshInterval)
        Defaults.ifPresent(key: .menuBarItemAlertRevealCooldown, assign: &menuBarItemAlertRevealCooldown)
        Defaults.ifPresent(key: .autoZenWhileSharingScreen, assign: &autoZenWhileSharingScreen)
        Defaults.ifPresent(key: .enableDiagnosticLogging, assign: &enableDiagnosticLogging)
        Defaults.ifPresent(key: .enableMenuBarItemOverflow, assign: &enableMenuBarItemOverflow)
        Defaults.ifPresent(key: .enableNativeAppHiding, assign: &enableNativeAppHiding)
        Defaults.ifPresent(key: .enableExperimentalSystemItemHiding, assign: &enableExperimentalSystemItemHiding)
        Defaults.ifPresent(key: .enableExperimentalOverflowPrevention, assign: &enableExperimentalOverflowPrevention)
        Defaults.ifPresent(key: .alwaysUseAppIconForMenuBarItems, assign: &alwaysUseAppIconForMenuBarItems)
        Defaults.ifPresent(key: .enableMenuBarItemDescenders, assign: &enableMenuBarItemDescenders)
        // Read the legacy key first so the current key takes precedence.
        Defaults.ifPresent(key: .legacyEnableTransportBar, assign: &enableSwapBar)
        Defaults.ifPresent(key: .enableSwapBar, assign: &enableSwapBar)
        Defaults.ifPresent(key: .swapOnThawIconClick, assign: &swapOnThawIconClick)
        Defaults.ifPresent(key: .enableControlItemPanel, assign: &enableControlItemPanel)
        Defaults.ifPresent(key: .fetchReleaseNotes, assign: &fetchReleaseNotes)
        Defaults.ifPresent(key: .enableModuleStandIns, assign: &enableModuleStandIns)
        Defaults.ifPresent(key: .enableTimeMachineTakeover, assign: &enableTimeMachineTakeover)
        Defaults.ifPresent(key: .enableTimerTakeover, assign: &enableTimerTakeover)
        Defaults.ifPresent(key: .enableTextInputTakeover, assign: &enableTextInputTakeover)
        Defaults.ifPresent(key: .enableRecordingWatch, assign: &enableRecordingWatch)
        Defaults.ifPresent(key: .zenModeWhileRecording, assign: &zenModeWhileRecording)
        Defaults.ifPresent(key: .recordingWatchScreen) { (raw: String) in
            if let choice = RecordingWatchScreen.from(storageKey: raw) {
                recordingWatchScreen = choice
            }
        }
        Defaults.ifPresent(key: .recordingWatchPlacement) { (raw: String) in
            if let placement = ThawHUDPlacement(rawValue: raw) {
                recordingWatchPlacement = placement
            }
        }
        Defaults.ifPresent(key: .enableDesktopMenuHiding, assign: &enableDesktopMenuHiding)
        Defaults.ifPresent(key: .menuBarOrderFulfillmentTimeout, assign: &menuBarOrderFulfillmentTimeout)
        Defaults.ifPresent(key: .searchIncludeVisible, assign: &searchIncludeVisible)
        Defaults.ifPresent(key: .searchIncludeHidden, assign: &searchIncludeHidden)
        Defaults.ifPresent(key: .searchIncludeAlwaysHidden, assign: &searchIncludeAlwaysHidden)

        Defaults.ifPresent(key: .menuBarSearchPresentation) { (raw: String) in
            if let presentation = SearchPresentation(rawValue: raw) {
                menuBarSearchPresentation = presentation
            }
        }

        Defaults.ifPresent(key: .sectionDividerStyle) { rawValue in
            if let style = SectionDividerStyle(rawValue: rawValue) {
                sectionDividerStyle = style
            }
        }

        Defaults.ifPresent(key: .menuBarArrangementMode) { rawValue in
            if let mode = MenuBarArrangementMode(rawValue: rawValue) {
                menuBarArrangementMode = mode
            }
        }

        Defaults.ifPresent(key: .searchSectionOrder) { (rawValues: [String]) in
            searchSectionOrder = Self.sanitizedSearchSectionOrder(from: rawValues)
        }
    }

    /// Keep each section once in preferred order, appending missing cases; unusable input yields the default order.
    static func sanitizedSearchSectionOrder(from rawValues: [String]) -> [MenuBarSection.Name] {
        var seen = Set<MenuBarSection.Name>()
        var ordered: [MenuBarSection.Name] = []
        for raw in rawValues {
            guard let name = MenuBarSection.Name(rawValue: raw), !seen.contains(name) else {
                continue
            }
            ordered.append(name)
            seen.insert(name)
        }
        for name in MenuBarSection.Name.allCases where !seen.contains(name) {
            ordered.append(name)
        }
        return ordered
    }

    /// didSet handles persistence; Combine only observes external Settings-URI changes.
    private func configureObservers() {
        var c = Set<AnyCancellable>()

        NotificationCenter.default
            .publisher(for: .settingsDidChangeViaURI)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleExternalSettingsChange(notification)
            }
            .store(in: &c)

        cancellables = c
    }

    /// Handles settings changed externally via Settings URI scheme.
    func handleExternalSettingsChange(_ notification: Notification) {
        guard let key = notification.userInfo?["key"] as? String else {
            return
        }

        if let boolValue = notification.userInfo?["value"] as? Bool {
            switch key {
            case "enableAlwaysHiddenSection":
                enableAlwaysHiddenSection = boolValue
            case "showAllSectionsOnUserDrag":
                showAllSectionsOnUserDrag = boolValue
            case "hideApplicationMenus":
                hideApplicationMenus = boolValue
            case "enableSecondaryContextMenu":
                enableSecondaryContextMenu = boolValue
            case "showMenuBarTooltips":
                showMenuBarTooltips = boolValue
            case "autoZenWhileSharingScreen":
                autoZenWhileSharingScreen = boolValue
            case "enableDiagnosticLogging":
                enableDiagnosticLogging = boolValue
            case "enableMenuBarItemOverflow":
                enableMenuBarItemOverflow = boolValue
            case "enableExperimentalSystemItemHiding":
                enableExperimentalSystemItemHiding = boolValue
            case "enableExperimentalOverflowPrevention":
                enableExperimentalOverflowPrevention = boolValue
            case "alwaysUseAppIconForMenuBarItems":
                alwaysUseAppIconForMenuBarItems = boolValue
            case "enableMenuBarItemDescenders":
                enableMenuBarItemDescenders = boolValue
            case "enableSwapBar":
                enableSwapBar = boolValue
            case "swapOnThawIconClick":
                swapOnThawIconClick = boolValue
            case "enableControlItemPanel":
                enableControlItemPanel = boolValue
            case "fetchReleaseNotes":
                fetchReleaseNotes = boolValue
            case "enableRecordingWatch":
                enableRecordingWatch = boolValue
            case "zenModeWhileRecording":
                zenModeWhileRecording = boolValue
            case "enableDesktopMenuHiding":
                enableDesktopMenuHiding = boolValue
            case "searchIncludeVisible":
                searchIncludeVisible = boolValue
            case "searchIncludeHidden":
                searchIncludeHidden = boolValue
            case "searchIncludeAlwaysHidden":
                searchIncludeAlwaysHidden = boolValue
            default:
                // Key not handled by AdvancedSettings
                break
            }
        }

        if let doubleValue = notification.userInfo?["doubleValue"] as? Double {
            switch key {
            case "showOnHoverDelay":
                showOnHoverDelay = doubleValue
            case "tooltipDelay":
                tooltipDelay = doubleValue
            case "iconRefreshInterval":
                iconRefreshInterval = doubleValue
            case "menuBarItemAlertRevealCooldown":
                menuBarItemAlertRevealCooldown = doubleValue
            case "menuBarOrderFulfillmentTimeout":
                menuBarOrderFulfillmentTimeout = doubleValue
            default:
                // Key not handled by AdvancedSettings
                break
            }
        }
    }
}

// MARK: Flag observation

extension AdvancedSettings {
    /// Calls onChange on the main actor for each change at keyPath, until
    /// the cancellable is cancelled. The current value is delivered first.
    func observe<Value: Equatable & Sendable>(
        _ keyPath: KeyPath<AdvancedSettings, Value>,
        onChange: @escaping @MainActor (Value) -> Void
    ) -> AnyCancellable {
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let changes = Observations { self[keyPath: keyPath] }
            for await value in changes {
                onChange(value)
            }
        }
        return AnyCancellable { task.cancel() }
    }
}
