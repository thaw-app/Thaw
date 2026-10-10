//
//  MenuBarEngineConfiguration.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Observation

/// Every setting the menu bar engine reads, as plain read-only data, so the
/// engine can run without AppState behind it. Writes go through an explicit
/// manager dependency instead.
@MainActor
protocol MenuBarEngineConfiguration: AnyObject, Observable {
    // Sections
    var isAlwaysHiddenSectionEnabled: Bool { get }
    var sectionDividerStyle: SectionDividerStyle { get }
    var showAllSectionsOnUserDrag: Bool { get }

    // Reveal gestures
    var showOnClick: Bool { get }
    var showOnHover: Bool { get }
    var showOnHoverDelay: TimeInterval { get }
    var showOnScroll: Bool { get }
    var swapOnThawIconClick: Bool { get }

    // Rehiding
    var autoRehide: Bool { get }
    var rehideStrategy: RehideStrategy { get }
    var rehideInterval: TimeInterval { get }
    var tempShowInterval: TimeInterval { get }

    // Presentation
    var showThawIcon: Bool { get }
    var thawIcon: ControlItemImageSet { get }
    var customThawIconIsTemplate: Bool { get }
    var hideApplicationMenus: Bool { get }
    var showMenuBarTooltips: Bool { get }
    var enableSecondaryContextMenu: Bool { get }
    var tooltipDelay: TimeInterval { get }
    var simpleMode: Bool { get }

    // Item handling
    var enableMenuBarItemOverflow: Bool { get }
    var enableExperimentalSystemItemHiding: Bool { get }
    var enableExperimentalOverflowPrevention: Bool { get }
    var iconRefreshInterval: TimeInterval { get }
    var alwaysUseAppIconForMenuBarItems: Bool { get }
    var menuBarOrderFulfillmentTimeout: TimeInterval { get }
}

/// Forwards to the per-pane settings models, so the engine sees one flat surface.
extension AppSettings {
    /// Used before performSetup(with:). Shared, since building one per read
    /// would touch UserDefaults on a hot path.
    @MainActor
    static let engineDefaults = AppSettings()
}

extension AppSettings: MenuBarEngineConfiguration {
    var isAlwaysHiddenSectionEnabled: Bool {
        advanced.isAlwaysHiddenSectionEnabled
    }

    var sectionDividerStyle: SectionDividerStyle {
        advanced.sectionDividerStyle
    }

    var showAllSectionsOnUserDrag: Bool {
        advanced.showAllSectionsOnUserDrag
    }

    var showOnClick: Bool {
        general.showOnClick
    }

    var showOnHover: Bool {
        general.showOnHover
    }

    var showOnHoverDelay: TimeInterval {
        advanced.showOnHoverDelay
    }

    var showOnScroll: Bool {
        general.showOnScroll
    }

    var swapOnThawIconClick: Bool {
        advanced.swapOnThawIconClick
    }

    var autoRehide: Bool {
        general.autoRehide
    }

    var rehideStrategy: RehideStrategy {
        general.rehideStrategy
    }

    var rehideInterval: TimeInterval {
        general.rehideInterval
    }

    var tempShowInterval: TimeInterval {
        general.tempShowInterval
    }

    var showThawIcon: Bool {
        general.showThawIcon
    }

    var thawIcon: ControlItemImageSet {
        general.thawIcon
    }

    var customThawIconIsTemplate: Bool {
        general.customThawIconIsTemplate
    }

    var hideApplicationMenus: Bool {
        advanced.hideApplicationMenus
    }

    var showMenuBarTooltips: Bool {
        advanced.showMenuBarTooltips
    }

    var enableSecondaryContextMenu: Bool {
        advanced.enableSecondaryContextMenu
    }

    var tooltipDelay: TimeInterval {
        advanced.tooltipDelay
    }

    var simpleMode: Bool {
        general.simpleMode
    }

    var enableMenuBarItemOverflow: Bool {
        advanced.enableMenuBarItemOverflow
    }

    var enableExperimentalSystemItemHiding: Bool {
        advanced.enableExperimentalSystemItemHiding
    }

    var enableExperimentalOverflowPrevention: Bool {
        advanced.enableExperimentalOverflowPrevention
    }

    var iconRefreshInterval: TimeInterval {
        advanced.iconRefreshInterval
    }

    var alwaysUseAppIconForMenuBarItems: Bool {
        advanced.alwaysUseAppIconForMenuBarItems
    }

    var menuBarOrderFulfillmentTimeout: TimeInterval {
        advanced.menuBarOrderFulfillmentTimeout
    }
}
