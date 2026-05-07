//
//  AdvancedSettings.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI

// MARK: - AdvancedSettings

/// Model for the app's Advanced settings.
@MainActor
final class AdvancedSettings: ObservableObject {
    /// A Boolean value that indicates whether the always-hidden section
    /// is enabled.
    @Published var enableAlwaysHiddenSection = Defaults.DefaultValue.enableAlwaysHiddenSection
    @Published var useOptionClickToShowAlwaysHiddenSection = Defaults.DefaultValue.useOptionClickToShowAlwaysHiddenSection

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

        Defaults.ifPresent(key: .sectionDividerStyle) { rawValue in
            if let style = SectionDividerStyle(rawValue: rawValue) {
                sectionDividerStyle = style
            }
        }
    }

    /// Configures the internal observers for the model.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $enableAlwaysHiddenSection.persistToDefaults(key: .enableAlwaysHiddenSection, in: &c)
        $useOptionClickToShowAlwaysHiddenSection.persistToDefaults(key: .useOptionClickToShowAlwaysHiddenSection, in: &c)
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
        $enableMenuBarItemOverflow.persistToDefaults(key: .enableMenuBarItemOverflow, in: &c)

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
            default:
                // Key not handled by AdvancedSettings
                break
            }
        }
    }
}
