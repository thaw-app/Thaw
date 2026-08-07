//
//  MenuBarSectionLayout.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// The measurable half of MenuBarSection, split out following the pattern the
// coverage exclusions describe: extract the algorithm code into a file that
// stays measured, then exclude the part whose substance cannot run in a unit
// test. LayoutSolver, PendingLedger, AXIdentityCatalog and ClickReactionVerifier
// came out of MenuBarItemManager the same way.
//
// Everything here is a value type or a function of its arguments: the section
// names, the presentation modes, the notch gap, and the three rules that decide
// how a section is shown. Covered by MenuBarSectionNameTests,
// NotchOverflowRevealTests and MenuBarSectionGeometryTests.
//
// The AdvancedSettings-reading overload of forcesIceBarForNotchOverflow stays
// in MenuBarSection.swift with the instance half -- show, hide, toggle,
// updateControlItemState, and the rehide task and event monitor -- all of which
// need a live ControlItem/NSStatusItem, an AppState and a real NSScreen. New
// decision logic belongs here, not there.

nonisolated extension MenuBarSection {
    /// The name of a menu bar section.
    nonisolated enum Name: String, CaseIterable, Codable {
        case visible
        case hidden
        case alwaysHidden

        /// A string to show in the interface.
        var displayString: String {
            switch self {
            case .visible: "Visible"
            case .hidden: "Hidden"
            case .alwaysHidden: "Always-Hidden"
            }
        }

        /// A string to use for logging purposes.
        var logString: String {
            switch self {
            case .visible: "visible section"
            case .hidden: "hidden section"
            case .alwaysHidden: "always-hidden section"
            }
        }

        /// Localized string key representation.
        var localized: LocalizedStringKey {
            switch self {
            case .visible: LocalizedStringKey("Visible")
            case .hidden: LocalizedStringKey("Hidden")
            case .alwaysHidden: LocalizedStringKey("Always-Hidden")
            }
        }
    }

    /// Whether notch overflow forces the Thaw Bar even though the display's own
    /// Thaw Bar setting is off.
    ///
    /// Split out as a pure function so the rule is testable without a live
    /// menu bar. Requires overflow to be enabled, the "use the Thaw Bar while
    /// items are overflowed" preference to be on, and items to actually be
    /// ejected right now.
    static func forcesIceBarForNotchOverflow(
        overflowEnabled: Bool,
        useThawBarOnOverflow: Bool,
        hasEjectedItems: Bool
    ) -> Bool {
        overflowEnabled && useThawBarOnOverflow && hasEjectedItems
    }

    /// Whether the given section presents in the Thaw Bar.
    ///
    /// `displayUsesThawBar` sends every section there. `alwaysHiddenUsesThawBar`
    /// sends the always-hidden section alone, leaving the hidden section to
    /// expand inline, which is the point of the setting: reaching the
    /// always-hidden items inline means expanding the hidden section too,
    /// since always-hidden items sit to the left of the hidden control item.
    ///
    /// Notch overflow can force the Thaw Bar on top of this; see
    /// ``forcesIceBarForNotchOverflow(overflowEnabled:useThawBarOnOverflow:hasEjectedItems:)``.
    static func usesThawBar(
        for name: Name,
        displayUsesThawBar: Bool,
        alwaysHiddenUsesThawBar: Bool
    ) -> Bool {
        if displayUsesThawBar {
            return true
        }
        return name == .alwaysHidden && alwaysHiddenUsesThawBar
    }

    /// The gap that macOS leaves to the left and right of the notch (in points).
    static let notchGap: CGFloat = 24

    /// The preferred way to present the section on the menu bar.
    nonisolated enum PresentationMode: Equatable {
        /// Show the items inline without modifying the application menus.
        case inline
        /// Show the items inline, but only after hiding the application menus.
        case inlineHidingApplicationMenus
        /// Fall back to the Thaw Bar.
        case iceBar
    }

    /// Calculates the usable inline width for menu bar items on a screen.
    static func usableInlineWidth(
        from appMenuRightEdge: CGFloat?,
        screenFrameMinX: CGFloat,
        screenVisibleMaxX: CGFloat,
        notchFrame: CGRect?
    ) -> CGFloat {
        let clampedAppMenuRightEdge = max(screenFrameMinX, appMenuRightEdge ?? screenFrameMinX)

        if let notchFrame {
            let usableLeftOfNotch = notchFrame.minX - notchGap
            let usableRightOfNotchStart = notchFrame.maxX + notchGap
            let leftWidth = max(0, usableLeftOfNotch - clampedAppMenuRightEdge)
            let rightWidth = max(0, screenVisibleMaxX - usableRightOfNotchStart)
            return leftWidth + rightWidth
        }

        return max(0, screenVisibleMaxX - clampedAppMenuRightEdge)
    }

    /// Decides whether inline presentation fits, optionally allowing the app
    /// menus to be hidden to recover more space.
    static func presentationMode(
        totalItemsWidth: CGFloat,
        appMenuRightEdge: CGFloat?,
        screenFrameMinX: CGFloat,
        screenVisibleMaxX: CGFloat,
        notchFrame: CGRect?,
        allowHidingApplicationMenus: Bool
    ) -> PresentationMode {
        let inlineWidth = usableInlineWidth(
            from: appMenuRightEdge,
            screenFrameMinX: screenFrameMinX,
            screenVisibleMaxX: screenVisibleMaxX,
            notchFrame: notchFrame
        )
        if totalItemsWidth <= inlineWidth {
            return .inline
        }

        guard allowHidingApplicationMenus else {
            return .iceBar
        }

        let inlineWidthWithoutAppMenus = usableInlineWidth(
            from: screenFrameMinX,
            screenFrameMinX: screenFrameMinX,
            screenVisibleMaxX: screenVisibleMaxX,
            notchFrame: notchFrame
        )
        if totalItemsWidth <= inlineWidthWithoutAppMenus {
            return .inlineHidingApplicationMenus
        }

        return .iceBar
    }
}
