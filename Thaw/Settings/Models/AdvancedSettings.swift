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

    /// The delay before showing on hover.
    @Published var showOnHoverDelay = Defaults.DefaultValue.showOnHoverDelay

    /// The delay before showing a tooltip when hovering over a menu bar item.
    @Published var tooltipDelay = Defaults.DefaultValue.tooltipDelay

    /// A Boolean value that indicates whether tooltips are shown when hovering
    /// over menu bar items in the actual menu bar (not just in the IceBar or settings).
    @Published var showMenuBarTooltips = Defaults.DefaultValue.showMenuBarTooltips

    /// The interval between icon image refreshes in panels (Ice Bar, search, layout).
    @Published var iconRefreshInterval = Defaults.DefaultValue.iconRefreshInterval

    /// A Boolean value that indicates whether diagnostic logging to file is enabled.
    @Published var enableDiagnosticLogging = Defaults.DefaultValue.enableDiagnosticLogging

    /// A Boolean value that indicates whether to use LCS sorting instead of
    /// full sorting on notched displays.
    @Published var useLCSSortingOnNotchedDisplays = Defaults.DefaultValue.useLCSSortingOnNotchedDisplays

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
        Defaults.ifPresent(key: .showOnHoverDelay, assign: &showOnHoverDelay)
        Defaults.ifPresent(key: .tooltipDelay, assign: &tooltipDelay)
        Defaults.ifPresent(key: .showMenuBarTooltips, assign: &showMenuBarTooltips)
        Defaults.ifPresent(key: .iconRefreshInterval, assign: &iconRefreshInterval)
        Defaults.ifPresent(key: .enableDiagnosticLogging, assign: &enableDiagnosticLogging)
        Defaults.ifPresent(key: .useLCSSortingOnNotchedDisplays, assign: &useLCSSortingOnNotchedDisplays)

        Defaults.ifPresent(key: .sectionDividerStyle) { rawValue in
            if let style = SectionDividerStyle(rawValue: rawValue) {
                sectionDividerStyle = style
            }
        }
    }

    /// Configures the internal observers for the model.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $enableAlwaysHiddenSection
            .receive(on: DispatchQueue.main)
            .sink { enable in
                Defaults.set(enable, forKey: .enableAlwaysHiddenSection)
            }
            .store(in: &c)

        $useOptionClickToShowAlwaysHiddenSection
            .receive(on: DispatchQueue.main)
            .sink { enable in
                Defaults.set(enable, forKey: .useOptionClickToShowAlwaysHiddenSection)
            }
            .store(in: &c)

        $showAllSectionsOnUserDrag
            .receive(on: DispatchQueue.main)
            .sink { showAll in
                Defaults.set(showAll, forKey: .showAllSectionsOnUserDrag)
            }
            .store(in: &c)

        $sectionDividerStyle
            .receive(on: DispatchQueue.main)
            .sink { style in
                Defaults.set(style.rawValue, forKey: .sectionDividerStyle)
            }
            .store(in: &c)

        $hideApplicationMenus
            .receive(on: DispatchQueue.main)
            .sink { shouldHide in
                Defaults.set(shouldHide, forKey: .hideApplicationMenus)
            }
            .store(in: &c)

        $enableSecondaryContextMenu
            .receive(on: DispatchQueue.main)
            .sink { enable in
                Defaults.set(enable, forKey: .enableSecondaryContextMenu)
            }
            .store(in: &c)

        $showOnHoverDelay
            .receive(on: DispatchQueue.main)
            .sink { delay in
                Defaults.set(delay, forKey: .showOnHoverDelay)
            }
            .store(in: &c)

        $tooltipDelay
            .receive(on: DispatchQueue.main)
            .sink { delay in
                Defaults.set(delay, forKey: .tooltipDelay)
            }
            .store(in: &c)

        $showMenuBarTooltips
            .receive(on: DispatchQueue.main)
            .sink { show in
                Defaults.set(show, forKey: .showMenuBarTooltips)
            }
            .store(in: &c)

        $iconRefreshInterval
            .receive(on: DispatchQueue.main)
            .sink { interval in
                Defaults.set(interval, forKey: .iconRefreshInterval)
            }
            .store(in: &c)

        $enableDiagnosticLogging
            .receive(on: DispatchQueue.main)
            .sink { enable in
                Defaults.set(enable, forKey: .enableDiagnosticLogging)
                DiagnosticLogger.shared.isEnabled = enable
            }
            .store(in: &c)

        $useLCSSortingOnNotchedDisplays
            .receive(on: DispatchQueue.main)
            .sink { enable in
                Defaults.set(enable, forKey: .useLCSSortingOnNotchedDisplays)
            }
            .store(in: &c)

        cancellables = c
    }
}
