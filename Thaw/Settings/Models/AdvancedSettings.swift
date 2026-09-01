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
        }
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
        // 1.x click-gesture migration (#1012): option-click and double-click
        // on the menu bar toggled the always-hidden section unconditionally
        // in 1.x. 2.0 replaced them with opt-in gates whose keys did not
        // exist for upgraders, so the gestures silently stopped working —
        // reported as "2.0 did not honor the settings from 1.2". Seed both
        // gates on when they have never been explicitly set; an explicit
        // choice (either value, including off) is never overwritten.
        if Defaults.object(forKey: .useOptionClickToShowAlwaysHiddenSection) == nil {
            Defaults.set(true, forKey: .useOptionClickToShowAlwaysHiddenSection)
        }
        if Defaults.object(forKey: .useDoubleClickToShowAlwaysHiddenSection) == nil {
            Defaults.set(true, forKey: .useDoubleClickToShowAlwaysHiddenSection)
        }

        Defaults.ifPresent(key: .enableAlwaysHiddenSection, assign: &enableAlwaysHiddenSection)
        Defaults.ifPresent(key: .useOptionClickToShowAlwaysHiddenSection, assign: &useOptionClickToShowAlwaysHiddenSection)
        Defaults.ifPresent(key: .useDoubleClickToShowAlwaysHiddenSection, assign: &useDoubleClickToShowAlwaysHiddenSection)
        Defaults.ifPresent(key: .showAllSectionsOnUserDrag, assign: &showAllSectionsOnUserDrag)
        Defaults.ifPresent(key: .hideApplicationMenus, assign: &hideApplicationMenus)
        Defaults.ifPresent(key: .enableSecondaryContextMenu, assign: &enableSecondaryContextMenu)
        Defaults.ifPresent(key: .enableSecondaryContextMenuQuit, assign: &enableSecondaryContextMenuQuit)
        Defaults.ifPresent(key: .showOnHoverDelay, assign: &showOnHoverDelay)
        Defaults.ifPresent(key: .tooltipDelay, assign: &tooltipDelay)
        Defaults.ifPresent(key: .showMenuBarTooltips, assign: &showMenuBarTooltips)
        Defaults.ifPresent(key: .iconRefreshInterval, assign: &iconRefreshInterval)
        Defaults.ifPresent(key: .enableDiagnosticLogging, assign: &enableDiagnosticLogging)
        Defaults.ifPresent(key: .enableMenuBarItemOverflow, assign: &enableMenuBarItemOverflow)
        Defaults.ifPresent(key: .automaticArrangementEnabled, assign: &automaticArrangementEnabled)
        Defaults.ifPresent(key: .useThawBarOnNotchOverflow, assign: &useThawBarOnNotchOverflow)
        Defaults.ifPresent(key: .useAXClickDelivery, assign: &useAXClickDelivery)
        Defaults.ifPresent(key: .searchIncludeVisible, assign: &searchIncludeVisible)
        Defaults.ifPresent(key: .searchIncludeHidden, assign: &searchIncludeHidden)
        Defaults.ifPresent(key: .searchIncludeAlwaysHidden, assign: &searchIncludeAlwaysHidden)
        Defaults.ifPresent(key: .moveCursorToRevealedItem, assign: &moveCursorToRevealedItem)

        Defaults.ifPresent(key: .sectionDividerStyle) { rawValue in
            if let style = SectionDividerStyle(rawValue: rawValue) {
                sectionDividerStyle = style
            }
        }

        Defaults.ifPresent(key: .searchSectionOrder) { (rawValues: [String]) in
            searchSectionOrder = Self.sanitizedSearchSectionOrder(from: rawValues)
        }
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
