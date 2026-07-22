//
//  AdvancedSettings.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import MenuBarModel
import SwiftUI

// MARK: - AdvancedSettings

/// Model for the app's Advanced settings.
@MainActor
final class AdvancedSettings: ObservableObject {
    /// A Boolean value that indicates whether the always-hidden section
    /// is enabled.
    @Published var enableAlwaysHiddenSection = Defaults.DefaultValue.enableAlwaysHiddenSection

    /// The *effective* state of the always-hidden section. Route behavior through
    /// this, not the raw ``enableAlwaysHiddenSection``.
    var isAlwaysHiddenSectionEnabled: Bool {
        enableAlwaysHiddenSection
    }

    @Published var useOptionClickToShowAlwaysHiddenSection = Defaults.DefaultValue.useOptionClickToShowAlwaysHiddenSection
    @Published var useDoubleClickToShowAlwaysHiddenSection = Defaults.DefaultValue.useDoubleClickToShowAlwaysHiddenSection

    /// A Boolean value that indicates whether to show all sections when
    /// the user is dragging items in the menu bar.
    @Published var showAllSectionsOnUserDrag = Defaults.DefaultValue.showAllSectionsOnUserDrag

    /// The display style for section divider control items.
    @Published var sectionDividerStyle = Defaults.DefaultValue.sectionDividerStyle

    /// A Boolean value that indicates whether the application menus
    /// should be hidden if needed to show all menu bar items.
    @Published var hideApplicationMenus = Defaults.DefaultValue.hideApplicationMenus

    /// A Boolean value that indicates whether to show a context menu
    /// when the user right-clicks the menu bar.
    @Published var enableSecondaryContextMenu = Defaults.DefaultValue.enableSecondaryContextMenu

    /// A Boolean value that indicates whether the secondary context menu
    /// includes a Quit item.
    @Published var enableSecondaryContextMenuQuit = Defaults.DefaultValue.enableSecondaryContextMenuQuit

    /// The delay before showing on hover.
    @Published var showOnHoverDelay = Defaults.DefaultValue.showOnHoverDelay

    /// The delay before showing a tooltip when hovering over a menu bar item.
    @Published var tooltipDelay = Defaults.DefaultValue.tooltipDelay

    /// A Boolean value that indicates whether tooltips are shown when hovering
    /// over menu bar items in the actual menu bar (not just in the IceBar or settings).
    @Published var showMenuBarTooltips = Defaults.DefaultValue.showMenuBarTooltips

    /// The interval between icon image refreshes in panels (Thaw Bar, search, layout).
    @Published var iconRefreshInterval = Defaults.DefaultValue.iconRefreshInterval

    /// A Boolean value that indicates whether diagnostic logging to file is enabled.
    @Published var enableDiagnosticLogging = Defaults.DefaultValue.enableDiagnosticLogging

    /// A Boolean value that indicates whether to use LCS sorting instead of
    /// full sorting on notched displays.
    @Published var useLCSSortingOnNotchedDisplays = Defaults.DefaultValue.useLCSSortingOnNotchedDisplays

    /// A Boolean value that controls whether profile-apply overflows menu bar
    /// items from visible to hidden when they don't fit on a notched display.
    /// Only affects notched displays; non-notched displays never use this path.
    @Published var enableMenuBarItemOverflow = Defaults.DefaultValue.enableMenuBarItemOverflow

    /// A Boolean value that allows macOS system items such as Clock, Control
    /// Center, and Siri to be assigned to hidden sections on macOS 27.
    @Published var enableExperimentalSystemItemHiding = Defaults.DefaultValue.enableExperimentalSystemItemHiding

    /// A Boolean value that hides third-party items by moving their windows
    /// off-screen via CGS instead of the assessment-mode
    /// assertion, so hiding one item no longer reflows the bar and ghosts
    /// dynamic neighbors such as iStat. Complements, not replaces, the assertion.
    @Published var enableExperimentalWindowHiding = Defaults.DefaultValue.enableExperimentalWindowHiding

    /// User-facing selector for the macOS 27 third-party hiding backend. The
    /// stored key retains its preview-build name for settings/profile backward
    /// compatibility; the mechanism now uses preferred-position weights, not
    /// per-item windows.
    var enablePositionHiding: Bool {
        get { enableExperimentalWindowHiding }
        set { enableExperimentalWindowHiding = newValue }
    }

    /// Attempts to prevent the macOS 27 native menu bar overflow (the chevron
    /// that collapses items when space runs out) by pushing hidden items'
    /// position weights to extreme values so they are collapsed first, keeping
    /// visible items on screen. Only applies on macOS 27+ notched displays.
    ///
    /// Experimental and URI/Defaults-only: intentionally has no Settings UI
    /// and no search entry (see `SearchIndex.baseNonSearchableProperties`).
    @Published var enableExperimentalOverflowPrevention = Defaults.DefaultValue.enableExperimentalOverflowPrevention

    /// A Boolean value that makes Thaw render menu bar items from their owning
    /// app's icon instead of the live screenshot crop, in the Thaw Bar and the
    /// layout editor. On macOS 27 the native overflow control can bleed into the
    /// hosting-window capture; this prevents that capture from being displayed.
    /// The real system menu bar is unaffected. macOS 27+ only.
    @Published var alwaysUseAppIconForMenuBarItems = Defaults.DefaultValue.alwaysUseAppIconForMenuBarItems

    /// Maximum time to wait for MenuBarAgent to apply a preferred-position
    /// reorder before Thaw continues with residual reconciliation.
    @Published var menuBarOrderFulfillmentTimeout = Defaults.DefaultValue.menuBarOrderFulfillmentTimeout

    /// The order in which menu bar sections appear in the search panel.
    @Published var searchSectionOrder: [MenuBarSection.Name] = Defaults.DefaultValue.searchSectionOrder
        .compactMap(MenuBarSection.Name.init(rawValue:))

    /// A Boolean value that indicates whether items from the visible section
    /// are included in the menu bar search panel.
    @Published var searchIncludeVisible = Defaults.DefaultValue.searchIncludeVisible

    /// A Boolean value that indicates whether items from the hidden section
    /// are included in the menu bar search panel.
    @Published var searchIncludeHidden = Defaults.DefaultValue.searchIncludeHidden

    /// A Boolean value that indicates whether items from the always-hidden section
    /// are included in the menu bar search panel.
    @Published var searchIncludeAlwaysHidden = Defaults.DefaultValue.searchIncludeAlwaysHidden

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// Performs the initial setup of the model.
    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
        configureCancellables()
    }

    /// Loads the model's initial state.
    private func loadInitialState() {
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
        Defaults.ifPresent(key: .useLCSSortingOnNotchedDisplays, assign: &useLCSSortingOnNotchedDisplays)
        Defaults.ifPresent(key: .enableMenuBarItemOverflow, assign: &enableMenuBarItemOverflow)
        Defaults.ifPresent(key: .enableExperimentalSystemItemHiding, assign: &enableExperimentalSystemItemHiding)
        Defaults.ifPresent(key: .enableExperimentalWindowHiding, assign: &enableExperimentalWindowHiding)
        Defaults.ifPresent(key: .enableExperimentalOverflowPrevention, assign: &enableExperimentalOverflowPrevention)
        Defaults.ifPresent(key: .alwaysUseAppIconForMenuBarItems, assign: &alwaysUseAppIconForMenuBarItems)
        Defaults.ifPresent(key: .menuBarOrderFulfillmentTimeout, assign: &menuBarOrderFulfillmentTimeout)
        Defaults.ifPresent(key: .searchIncludeVisible, assign: &searchIncludeVisible)
        Defaults.ifPresent(key: .searchIncludeHidden, assign: &searchIncludeHidden)
        Defaults.ifPresent(key: .searchIncludeAlwaysHidden, assign: &searchIncludeAlwaysHidden)

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

    /// Configures the internal observers for the model.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $enableAlwaysHiddenSection.persistToDefaults(key: .enableAlwaysHiddenSection, in: &c)
        $useOptionClickToShowAlwaysHiddenSection.persistToDefaults(key: .useOptionClickToShowAlwaysHiddenSection, in: &c)
        $useDoubleClickToShowAlwaysHiddenSection.persistToDefaults(key: .useDoubleClickToShowAlwaysHiddenSection, in: &c)
        $showAllSectionsOnUserDrag.persistToDefaults(key: .showAllSectionsOnUserDrag, in: &c)
        $sectionDividerStyle.persistToDefaults(key: .sectionDividerStyle, transform: \.rawValue, in: &c)
        $hideApplicationMenus.persistToDefaults(key: .hideApplicationMenus, in: &c)
        $enableSecondaryContextMenu.persistToDefaults(key: .enableSecondaryContextMenu, in: &c)
        $enableSecondaryContextMenuQuit.persistToDefaults(key: .enableSecondaryContextMenuQuit, in: &c)
        $showOnHoverDelay.persistToDefaults(key: .showOnHoverDelay, in: &c)
        $tooltipDelay.persistToDefaults(key: .tooltipDelay, in: &c)
        $showMenuBarTooltips.persistToDefaults(key: .showMenuBarTooltips, in: &c)
        $iconRefreshInterval.persistToDefaults(key: .iconRefreshInterval, in: &c)
        $enableDiagnosticLogging.persistToDefaults(
            key: .enableDiagnosticLogging,
            sideEffect: { enabled in
                #if DEBUG
                    // Debug builds keep logging on regardless of profile swaps
                    // or user toggles so we never miss capture during dev.
                    DiagnosticLogger.shared.isEnabled = true
                #else
                    DiagnosticLogger.shared.isEnabled = enabled
                #endif
            },
            in: &c
        )
        $useLCSSortingOnNotchedDisplays.persistToDefaults(key: .useLCSSortingOnNotchedDisplays, in: &c)
        $enableMenuBarItemOverflow.persistToDefaults(
            key: .enableMenuBarItemOverflow,
            sideEffect: { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let itemManager = self?.appState?.itemManager else { return }
                    if await itemManager.rebalanceMacOS27OverflowIfNeeded(force: true) {
                        await itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
                    }
                }
            },
            in: &c
        )
        $enableExperimentalSystemItemHiding.persistToDefaults(key: .enableExperimentalSystemItemHiding, in: &c)
        $enableExperimentalWindowHiding.persistToDefaults(key: .enableExperimentalWindowHiding, in: &c)
        $enableExperimentalOverflowPrevention.persistToDefaults(key: .enableExperimentalOverflowPrevention, in: &c)
        $alwaysUseAppIconForMenuBarItems.persistToDefaults(key: .alwaysUseAppIconForMenuBarItems, in: &c)
        $menuBarOrderFulfillmentTimeout.persistToDefaults(key: .menuBarOrderFulfillmentTimeout, in: &c)
        $searchSectionOrder.persistToDefaults(
            key: .searchSectionOrder,
            transform: { $0.map(\.rawValue) },
            in: &c
        )
        $searchIncludeVisible.persistToDefaults(key: .searchIncludeVisible, in: &c)
        $searchIncludeHidden.persistToDefaults(key: .searchIncludeHidden, in: &c)
        $searchIncludeAlwaysHidden.persistToDefaults(key: .searchIncludeAlwaysHidden, in: &c)

        // Observe external settings changes via Settings URI
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
    private func handleExternalSettingsChange(_ notification: Notification) {
        guard let key = notification.userInfo?["key"] as? String else {
            return
        }

        // Handle boolean values
        if let boolValue = notification.userInfo?["value"] as? Bool {
            switch key {
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
            case "useLCSSortingOnNotchedDisplays":
                useLCSSortingOnNotchedDisplays = boolValue
            case "enableMenuBarItemOverflow":
                enableMenuBarItemOverflow = boolValue
            case "enableExperimentalSystemItemHiding":
                enableExperimentalSystemItemHiding = boolValue
            case "enableExperimentalWindowHiding":
                enableExperimentalWindowHiding = boolValue
            case "enableExperimentalOverflowPrevention":
                enableExperimentalOverflowPrevention = boolValue
            case "alwaysUseAppIconForMenuBarItems":
                alwaysUseAppIconForMenuBarItems = boolValue
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

        // Handle double values
        if let doubleValue = notification.userInfo?["doubleValue"] as? Double {
            switch key {
            case "showOnHoverDelay":
                showOnHoverDelay = doubleValue
            case "tooltipDelay":
                tooltipDelay = doubleValue
            case "iconRefreshInterval":
                iconRefreshInterval = doubleValue
            case "menuBarOrderFulfillmentTimeout":
                menuBarOrderFulfillmentTimeout = doubleValue
            default:
                // Key not handled by AdvancedSettings
                break
            }
        }
    }
}
