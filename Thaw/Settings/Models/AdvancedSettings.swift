//
//  AdvancedSettings.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
import Combine
import SwiftUI

// MARK: - AdvancedSettings

/// Model for the app's Advanced settings.
@MainActor
@Observable
final class AdvancedSettings {
    /// A Boolean value that indicates whether the always-hidden section
    /// is enabled.
    var enableAlwaysHiddenSection = Defaults.DefaultValue.enableAlwaysHiddenSection {
        didSet {
            guard oldValue != enableAlwaysHiddenSection else { return }
            Defaults.set(enableAlwaysHiddenSection, forKey: .enableAlwaysHiddenSection)
        }
    }

    var useOptionClickToShowAlwaysHiddenSection = Defaults.DefaultValue.useOptionClickToShowAlwaysHiddenSection {
        didSet {
            guard oldValue != useOptionClickToShowAlwaysHiddenSection else { return }
            Defaults.set(useOptionClickToShowAlwaysHiddenSection, forKey: .useOptionClickToShowAlwaysHiddenSection)
        }
    }

    var useDoubleClickToShowAlwaysHiddenSection = Defaults.DefaultValue.useDoubleClickToShowAlwaysHiddenSection {
        didSet {
            guard oldValue != useDoubleClickToShowAlwaysHiddenSection else { return }
            Defaults.set(useDoubleClickToShowAlwaysHiddenSection, forKey: .useDoubleClickToShowAlwaysHiddenSection)
        }
    }

    /// A Boolean value that indicates whether to show all sections when
    /// the user is dragging items in the menu bar.
    var showAllSectionsOnUserDrag = Defaults.DefaultValue.showAllSectionsOnUserDrag {
        didSet {
            guard oldValue != showAllSectionsOnUserDrag else { return }
            Defaults.set(showAllSectionsOnUserDrag, forKey: .showAllSectionsOnUserDrag)
        }
    }

    /// The display style for section divider control items.
    var sectionDividerStyle = Defaults.DefaultValue.sectionDividerStyle {
        didSet {
            guard oldValue != sectionDividerStyle else { return }
            Defaults.set(sectionDividerStyle.rawValue, forKey: .sectionDividerStyle)
        }
    }

    /// A Boolean value that indicates whether the application menus
    /// should be hidden if needed to show all menu bar items.
    var hideApplicationMenus = Defaults.DefaultValue.hideApplicationMenus {
        didSet {
            guard oldValue != hideApplicationMenus else { return }
            Defaults.set(hideApplicationMenus, forKey: .hideApplicationMenus)
        }
    }

    /// A Boolean value that indicates whether to show a context menu
    /// when the user right-clicks the menu bar.
    var enableSecondaryContextMenu = Defaults.DefaultValue.enableSecondaryContextMenu {
        didSet {
            guard oldValue != enableSecondaryContextMenu else { return }
            Defaults.set(enableSecondaryContextMenu, forKey: .enableSecondaryContextMenu)
        }
    }

    /// A Boolean value that indicates whether the secondary context menu
    /// includes a Quit item.
    var enableSecondaryContextMenuQuit = Defaults.DefaultValue.enableSecondaryContextMenuQuit {
        didSet {
            guard oldValue != enableSecondaryContextMenuQuit else { return }
            Defaults.set(enableSecondaryContextMenuQuit, forKey: .enableSecondaryContextMenuQuit)
        }
    }

    /// The delay before showing on hover.
    var showOnHoverDelay = Defaults.DefaultValue.showOnHoverDelay {
        didSet {
            guard oldValue != showOnHoverDelay else { return }
            Defaults.set(showOnHoverDelay, forKey: .showOnHoverDelay)
        }
    }

    /// The delay before showing a tooltip when hovering over a menu bar item.
    var tooltipDelay = Defaults.DefaultValue.tooltipDelay {
        didSet {
            guard oldValue != tooltipDelay else { return }
            Defaults.set(tooltipDelay, forKey: .tooltipDelay)
        }
    }

    /// A Boolean value that indicates whether tooltips are shown when hovering
    /// over menu bar items in the actual menu bar (not just in the IceBar or settings).
    var showMenuBarTooltips = Defaults.DefaultValue.showMenuBarTooltips {
        didSet {
            guard oldValue != showMenuBarTooltips else { return }
            Defaults.set(showMenuBarTooltips, forKey: .showMenuBarTooltips)
        }
    }

    /// The interval between icon image refreshes in panels (Thaw Bar, search, layout).
    ///
    /// Always held on the discrete grid the "Icon refresh rate" slider can
    /// express: `0` (Off) or `1/n` for `n` in `1...maxIconRefreshRate`. Writes
    /// from the slider, URI, profiles, and Defaults load are all snapped here
    /// so the UI and the live-refresh loop never disagree.
    var iconRefreshInterval = Defaults.DefaultValue.iconRefreshInterval {
        didSet {
            let normalized = Self.normalizedIconRefreshInterval(iconRefreshInterval)
            let didNormalize = iconRefreshInterval != normalized
            if didNormalize {
                iconRefreshInterval = normalized
            }
            guard didNormalize || oldValue != iconRefreshInterval else { return }
            Defaults.set(iconRefreshInterval, forKey: .iconRefreshInterval)
        }
    }

    /// Snaps an icon-refresh interval onto the values the slider can express.
    ///
    /// - `<= 0` stays Off (`0`).
    /// - Otherwise snaps to `1 / clamp(round(1 / interval), 1, ceiling)`,
    ///   where the ceiling is ``MenuBarItemImageCache/maxIconRefreshRate``.
    /// - Idempotent: already-on-grid values round-trip unchanged.
    static nonisolated func normalizedIconRefreshInterval(_ interval: TimeInterval) -> TimeInterval {
        guard interval > 0 else { return 0 }
        let ceiling = MenuBarItemImageCache.maxIconRefreshRate
        let fps = min(max((1.0 / interval).rounded(), 1), ceiling)
        return 1.0 / fps
    }

    /// A Boolean value that indicates whether zen mode engages by itself while
    /// the screen is mirrored or being shared. See ``PresentationMonitor`` for
    /// what that does and does not detect.
    var autoZenWhileSharingScreen = Defaults.DefaultValue.autoZenWhileSharingScreen {
        didSet {
            guard oldValue != autoZenWhileSharingScreen else { return }
            Defaults.set(autoZenWhileSharingScreen, forKey: .autoZenWhileSharingScreen)
        }
    }

    /// A Boolean value that indicates whether diagnostic logging to file is enabled.
    var enableDiagnosticLogging = Defaults.DefaultValue.enableDiagnosticLogging {
        didSet {
            guard oldValue != enableDiagnosticLogging else { return }
            Defaults.set(enableDiagnosticLogging, forKey: .enableDiagnosticLogging)
            #if DEBUG
                // Debug builds keep logging on regardless of profile swaps
                // or user toggles so we never miss capture during dev.
                DiagnosticLogger.shared.isEnabled = true
            #else
                DiagnosticLogger.shared.isEnabled = enableDiagnosticLogging
            #endif
            // The XPC service holds its own handle on the shared file, so a
            // toggle has to reach it too: a file to follow, or nothing to stop.
            Task { await MenuBarItemService.Connection.shared.syncLogging() }
        }
    }

    /// The size, in megabytes, a diagnostic log file may reach before it is
    /// rotated to a new file.
    var diagnosticLogMaxSizeMB = Defaults.DefaultValue.diagnosticLogMaxSizeMB {
        didSet {
            guard oldValue != diagnosticLogMaxSizeMB else { return }
            Defaults.set(diagnosticLogMaxSizeMB, forKey: .diagnosticLogMaxSizeMB)
            applyLogRotationPolicy(pushingToService: true)
        }
    }

    /// How many days diagnostic log files are kept before they are deleted.
    var diagnosticLogRetentionDays = Defaults.DefaultValue.diagnosticLogRetentionDays {
        didSet {
            guard oldValue != diagnosticLogRetentionDays else { return }
            Defaults.set(diagnosticLogRetentionDays, forKey: .diagnosticLogRetentionDays)
            applyLogRotationPolicy(pushingToService: true)
        }
    }

    /// How often diagnostic logs are rotated on a schedule, on top of the size
    /// limit.
    var diagnosticLogRotationInterval = Defaults.DefaultValue.diagnosticLogRotationInterval {
        didSet {
            guard oldValue != diagnosticLogRotationInterval else { return }
            Defaults.set(diagnosticLogRotationInterval.rawValue, forKey: .diagnosticLogRotationInterval)
            applyLogRotationPolicy(pushingToService: true)
        }
    }

    /// True while ``loadInitialState()`` runs.
    ///
    /// Assigning a loaded value trips that property's `didSet`, so without this
    /// the service would be sent a policy once per setting, each one built from
    /// a half-loaded model, before the connection has even started.
    @ObservationIgnored
    private var isLoadingInitialState = false

    /// The largest log size the app will ask the logger for.
    ///
    /// Far above anything the settings stepper offers; it exists only so a
    /// value read back from a profile or from UserDefaults cannot overflow the
    /// conversion to bytes.
    private static let maxDiagnosticLogSizeMB = 1_000_000

    /// Hands the current rotation settings to the diagnostic logger, and — once
    /// the app is running — to the XPC service that shares the log directory.
    ///
    /// - Parameter pushingToService: Whether to forward the policy over XPC.
    ///   Left off during initialization, when the connection has not started
    ///   yet and `Connection.start()` sends the initial configuration anyway.
    func applyLogRotationPolicy(pushingToService: Bool = false) {
        DiagnosticLogger.shared.setRotationPolicy(
            Self.rotationPolicy(
                maxSizeMB: diagnosticLogMaxSizeMB,
                retentionDays: diagnosticLogRetentionDays,
                interval: diagnosticLogRotationInterval
            )
        )

        guard pushingToService, !isLoadingInitialState else { return }
        Task { await MenuBarItemService.Connection.shared.syncLogging() }
    }

    /// Builds a rotation policy from the given settings.
    static func rotationPolicy(
        maxSizeMB: Int,
        retentionDays: Int,
        interval: LogRotationInterval
    ) -> DiagnosticLogger.RotationPolicy {
        var policy = DiagnosticLogger.RotationPolicy()
        // Clamped before the multiplication: UserDefaults can hold values the
        // stepper would never produce, and `UInt64(huge) * 1024 * 1024` traps
        // on overflow.
        let megabytes = min(max(0, maxSizeMB), maxDiagnosticLogSizeMB)
        policy.maxFileSizeBytes = UInt64(megabytes) * 1024 * 1024
        policy.retentionDays = max(1, retentionDays)
        policy.rotationInterval = interval.seconds
        return policy
    }

    /// Reads a rotation policy straight out of the stored settings.
    ///
    /// Diagnostic logging starts before this model is built, and opening a log
    /// file prunes the directory. Without this the first prune of every launch
    /// would run against the default retention and delete files that a longer
    /// setting was meant to keep.
    static func persistedRotationPolicy() -> DiagnosticLogger.RotationPolicy {
        var maxSizeMB = Defaults.DefaultValue.diagnosticLogMaxSizeMB
        var retentionDays = Defaults.DefaultValue.diagnosticLogRetentionDays
        var interval = Defaults.DefaultValue.diagnosticLogRotationInterval

        Defaults.ifPresent(key: .diagnosticLogMaxSizeMB, assign: &maxSizeMB)
        Defaults.ifPresent(key: .diagnosticLogRetentionDays, assign: &retentionDays)
        Defaults.ifPresent(key: .diagnosticLogRotationInterval) { (rawValue: String) in
            if let stored = LogRotationInterval(rawValue: rawValue) {
                interval = stored
            }
        }

        return rotationPolicy(maxSizeMB: maxSizeMB, retentionDays: retentionDays, interval: interval)
    }

    /// A Boolean value that controls whether profile-apply overflows menu bar
    /// items from visible to hidden when they don't fit on a notched display.
    /// Only affects notched displays; non-notched displays never use this path.
    var enableMenuBarItemOverflow = Defaults.DefaultValue.enableMenuBarItemOverflow {
        didSet {
            guard oldValue != enableMenuBarItemOverflow else { return }
            Defaults.set(enableMenuBarItemOverflow, forKey: .enableMenuBarItemOverflow)
        }
    }

    /// A Boolean value that controls whether Thaw rearranges the menu bar on
    /// its own initiative.
    ///
    /// The escape hatch for bars where the automatic paths misbehave. When
    /// off, the late-arrival re-sort and the saved-layout restore both stand
    /// down; applying a profile still works, and items can still be arranged
    /// by ⌘ Command + dragging them in the menu bar. Read at the single
    /// choke point in `MenuBarItemManager.applyProfileLayout`, which is also
    /// where the graduated responses (the idle gate, concealed-order
    /// relaxation, unfinished-batch rationing) live.
    var automaticArrangementEnabled = Defaults.DefaultValue.automaticArrangementEnabled {
        didSet {
            guard oldValue != automaticArrangementEnabled else { return }
            Defaults.set(automaticArrangementEnabled, forKey: .automaticArrangementEnabled)
        }
    }

    /// A Boolean value that controls whether the Thaw Bar is used to reveal
    /// hidden items while notch overflow has items ejected.
    ///
    /// Expanding the hidden section inline cannot show items that overflow
    /// ejected: they were ejected precisely because the visible row had no room
    /// left beside the notch. When this is on, a display with ejected items
    /// reveals through the Thaw Bar regardless of its per-display Thaw Bar
    /// setting. Only affects displays that currently have ejected items.
    var useThawBarOnNotchOverflow = Defaults.DefaultValue.useThawBarOnNotchOverflow {
        didSet {
            guard oldValue != useThawBarOnNotchOverflow else { return }
            Defaults.set(useThawBarOnNotchOverflow, forKey: .useThawBarOnNotchOverflow)
        }
    }

    /// A Boolean value that controls whether left-clicks on menu bar items
    /// from the IceBar are delivered via an accessibility action (AXShowMenu,
    /// falling back to AXPress) instead of a synthetic mouse click.
    /// Default on and no longer surfaced in Settings; automatically falls
    /// back to the synthetic click on any failure. Moves and right-clicks
    /// are unaffected.
    var useAXClickDelivery = Defaults.DefaultValue.useAXClickDelivery {
        didSet {
            guard oldValue != useAXClickDelivery else { return }
            Defaults.set(useAXClickDelivery, forKey: .useAXClickDelivery)
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

    /// A Boolean value that indicates whether items from the visible section
    /// are included in the menu bar search panel.
    var searchIncludeVisible = Defaults.DefaultValue.searchIncludeVisible {
        didSet {
            guard oldValue != searchIncludeVisible else { return }
            Defaults.set(searchIncludeVisible, forKey: .searchIncludeVisible)
        }
    }

    /// A Boolean value that indicates whether items from the hidden section
    /// are included in the menu bar search panel.
    var searchIncludeHidden = Defaults.DefaultValue.searchIncludeHidden {
        didSet {
            guard oldValue != searchIncludeHidden else { return }
            Defaults.set(searchIncludeHidden, forKey: .searchIncludeHidden)
        }
    }

    /// A Boolean value that indicates whether items from the always-hidden section
    /// are included in the menu bar search panel.
    var searchIncludeAlwaysHidden = Defaults.DefaultValue.searchIncludeAlwaysHidden {
        didSet {
            guard oldValue != searchIncludeAlwaysHidden else { return }
            Defaults.set(searchIncludeAlwaysHidden, forKey: .searchIncludeAlwaysHidden)
        }
    }

    /// A Boolean value that indicates whether the mouse pointer is moved to a
    /// menu bar item that was opened from the search panel.
    ///
    /// Only the search panel warps the pointer. Opening an item from the Thaw
    /// Bar means the pointer is already there, so moving it would only take it
    /// somewhere the user did not put it.
    var moveCursorToRevealedItem = Defaults.DefaultValue.moveCursorToRevealedItem {
        didSet {
            guard oldValue != moveCursorToRevealedItem else { return }
            Defaults.set(moveCursorToRevealedItem, forKey: .moveCursorToRevealedItem)
        }
    }

    /// Whether menu bar items are drawn as their owning application's icon
    /// instead of a live capture.
    ///
    /// Applies everywhere Thaw renders an item — the Thaw Bar, the layout
    /// editor and the search panel. Distinct from the automatic fallback,
    /// which only substitutes an icon where no capture exists: this asks for
    /// icons even when a capture is available, for people who find live
    /// previews noisy or would rather not have their menu bar sampled.
    var alwaysUseAppIconForMenuBarItems = Defaults.DefaultValue.alwaysUseAppIconForMenuBarItems {
        didSet {
            guard oldValue != alwaysUseAppIconForMenuBarItems else { return }
            Defaults.set(alwaysUseAppIconForMenuBarItems, forKey: .alwaysUseAppIconForMenuBarItems)
        }
    }

    /// Whether an item that starts blinking while hidden briefly shows its
    /// section, so an alert raised behind the chevron is still seen.
    ///
    /// Off by default. The verdict is a heuristic read off the item's own
    /// pixels, and acting on a wrong one moves the bar the user arranged.
    var surfaceItemsSeekingAttention = Defaults.DefaultValue.surfaceItemsSeekingAttention {
        didSet {
            guard oldValue != surfaceItemsSeekingAttention else { return }
            Defaults.set(surfaceItemsSeekingAttention, forKey: .surfaceItemsSeekingAttention)
        }
    }

    /// Storage for internal observers.
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    /// The shared app state.
    @ObservationIgnored
    private(set) weak var appState: AppState?

    /// Performs the initial setup of the model.
    ///
    /// The app state is only stored, never read, by this model: the setup it
    /// performs is reading `Defaults` and subscribing to the Settings-URI
    /// notification. The parameter is optional so that setup can be driven
    /// without standing up an ``AppState``; the app always passes one.
    func performSetup(with appState: AppState? = nil) {
        self.appState = appState
        loadInitialState()
        configureObservers()
    }

    /// Loads the model's initial state.
    private func loadInitialState() {
        isLoadingInitialState = true
        defer { isLoadingInitialState = false }

        Defaults.ifPresent(key: .enableAlwaysHiddenSection, assign: &enableAlwaysHiddenSection)
        Defaults.ifPresent(key: .useOptionClickToShowAlwaysHiddenSection, assign: &useOptionClickToShowAlwaysHiddenSection)
        Defaults.ifPresent(key: .useDoubleClickToShowAlwaysHiddenSection, assign: &useDoubleClickToShowAlwaysHiddenSection)
        Defaults.ifPresent(key: .showAllSectionsOnUserDrag, assign: &showAllSectionsOnUserDrag)
        Defaults.ifPresent(key: .hideApplicationMenus, assign: &hideApplicationMenus)
        Defaults.ifPresent(key: .enableSecondaryContextMenu, assign: &enableSecondaryContextMenu)
        Defaults.ifPresent(key: .enableSecondaryContextMenuQuit, assign: &enableSecondaryContextMenuQuit)
        Defaults.ifPresent(key: .showOnHoverDelay, assign: &showOnHoverDelay)
        Defaults.ifPresent(key: .tooltipDelay, assign: &tooltipDelay)
        Defaults.ifPresent(key: .autoZenWhileSharingScreen, assign: &autoZenWhileSharingScreen)
        Defaults.ifPresent(key: .showMenuBarTooltips, assign: &showMenuBarTooltips)
        Defaults.ifPresent(key: .iconRefreshInterval, assign: &iconRefreshInterval)
        Defaults.ifPresent(key: .enableDiagnosticLogging, assign: &enableDiagnosticLogging)
        Defaults.ifPresent(key: .diagnosticLogMaxSizeMB, assign: &diagnosticLogMaxSizeMB)
        Defaults.ifPresent(key: .diagnosticLogRetentionDays, assign: &diagnosticLogRetentionDays)
        Defaults.ifPresent(key: .diagnosticLogRotationInterval) { (rawValue: String) in
            if let interval = LogRotationInterval(rawValue: rawValue) {
                diagnosticLogRotationInterval = interval
            }
        }
        Defaults.ifPresent(key: .enableMenuBarItemOverflow, assign: &enableMenuBarItemOverflow)
        Defaults.ifPresent(key: .automaticArrangementEnabled, assign: &automaticArrangementEnabled)
        Defaults.ifPresent(key: .useThawBarOnNotchOverflow, assign: &useThawBarOnNotchOverflow)
        Defaults.ifPresent(key: .useAXClickDelivery, assign: &useAXClickDelivery)
        Defaults.ifPresent(key: .searchIncludeVisible, assign: &searchIncludeVisible)
        Defaults.ifPresent(key: .searchIncludeHidden, assign: &searchIncludeHidden)
        Defaults.ifPresent(key: .searchIncludeAlwaysHidden, assign: &searchIncludeAlwaysHidden)
        Defaults.ifPresent(key: .moveCursorToRevealedItem, assign: &moveCursorToRevealedItem)
        Defaults.ifPresent(key: .surfaceItemsSeekingAttention, assign: &surfaceItemsSeekingAttention)
        Defaults.ifPresent(key: .alwaysUseAppIconForMenuBarItems, assign: &alwaysUseAppIconForMenuBarItems)

        Defaults.ifPresent(key: .sectionDividerStyle) { rawValue in
            if let style = SectionDividerStyle(rawValue: rawValue) {
                sectionDividerStyle = style
            }
        }

        Defaults.ifPresent(key: .searchSectionOrder) { (rawValues: [String]) in
            searchSectionOrder = Self.sanitizedSearchSectionOrder(from: rawValues)
        }

        // One authoritative apply once every setting is in place. The `didSet`
        // observers tripped above each applied a partially loaded policy, and
        // none of them reached the service.
        applyLogRotationPolicy()
    }

    /// Returns a search-section order that contains each `MenuBarSection.Name`
    /// case exactly once, using the supplied raw values as the preferred order
    /// and filling any missing cases at the end. Returns the default order if
    /// the input is unusable.
    static func sanitizedSearchSectionOrder(from rawValues: [String]) -> [MenuBarSection.Name] {
        let preferred = Array(
            rawValues.compactMap(MenuBarSection.Name.init(rawValue:)).uniqued()
        )
        return preferred + MenuBarSection.Name.allCases.filter { !preferred.contains($0) }
    }

    /// Configures the internal observers for the model.
    ///
    /// Persistence for most properties is now driven by `didSet` on each
    /// property (see above), replacing the previous `$property.persistToDefaults`
    /// Combine pipelines. Only the Settings-URI notification subscription
    /// remains Combine-based here.
    private func configureObservers() {
        cancellables = [
            NotificationCenter.observeSettingsChangesViaURI { [weak self] change in
                self?.handleExternalSettingsChange(change)
            },
        ]
    }

    /// Handles settings changed externally via Settings URI scheme.
    private func handleExternalSettingsChange(_ change: ExternalSettingsChange) {
        // Handle boolean values
        if let boolValue = change.boolValue {
            switch change.key {
            case "enableAlwaysHiddenSection":
                enableAlwaysHiddenSection = boolValue
            case "useOptionClickToShowAlwaysHiddenSection":
                useOptionClickToShowAlwaysHiddenSection = boolValue
            case "useDoubleClickToShowAlwaysHiddenSection":
                useDoubleClickToShowAlwaysHiddenSection = boolValue
            case "showAllSectionsOnUserDrag":
                showAllSectionsOnUserDrag = boolValue
            case "hideApplicationMenus":
                hideApplicationMenus = boolValue
            case "enableSecondaryContextMenu":
                enableSecondaryContextMenu = boolValue
            case "enableSecondaryContextMenuQuit":
                enableSecondaryContextMenuQuit = boolValue
            case "showMenuBarTooltips":
                showMenuBarTooltips = boolValue
            case "enableDiagnosticLogging":
                enableDiagnosticLogging = boolValue
            case "enableMenuBarItemOverflow":
                enableMenuBarItemOverflow = boolValue
            case "automaticArrangementEnabled":
                automaticArrangementEnabled = boolValue
            case "useThawBarOnNotchOverflow":
                useThawBarOnNotchOverflow = boolValue
            case "useAXClickDelivery":
                useAXClickDelivery = boolValue
            case "searchIncludeVisible":
                searchIncludeVisible = boolValue
            case "searchIncludeHidden":
                searchIncludeHidden = boolValue
            case "searchIncludeAlwaysHidden":
                searchIncludeAlwaysHidden = boolValue
            case "moveCursorToRevealedItem":
                moveCursorToRevealedItem = boolValue
            case "surfaceItemsSeekingAttention":
                surfaceItemsSeekingAttention = boolValue
            case "alwaysUseAppIconForMenuBarItems":
                alwaysUseAppIconForMenuBarItems = boolValue
            default:
                // Key not handled by AdvancedSettings
                break
            }
        }

        // Handle double values
        if let doubleValue = change.doubleValue {
            switch change.key {
            case "showOnHoverDelay":
                showOnHoverDelay = doubleValue
            case "tooltipDelay":
                tooltipDelay = doubleValue
            case "iconRefreshInterval":
                iconRefreshInterval = doubleValue
            default:
                // Key not handled by AdvancedSettings
                break
            }
        }
    }
}
