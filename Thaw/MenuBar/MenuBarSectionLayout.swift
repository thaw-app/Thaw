//
//  MenuBarSectionLayout.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// The pure, unit-tested half of MenuBarSection. The instance half in
// MenuBarSection.swift needs a live ControlItem, AppState and NSScreen, and is
// excluded from coverage. New decision logic belongs here, not there.

nonisolated extension MenuBarSection {
    /// The name of a menu bar section.
    nonisolated enum Name: String, CaseIterable, Codable {
        case visible
        case hidden
        case alwaysHidden

        var displayString: String {
            switch self {
            case .visible: "Visible"
            case .hidden: "Hidden"
            case .alwaysHidden: "Always-Hidden"
            }
        }

        var logString: String {
            switch self {
            case .visible: "visible section"
            case .hidden: "hidden section"
            case .alwaysHidden: "always-hidden section"
            }
        }

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
    /// sends only always-hidden, since reaching it inline also expands hidden.
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

    /// The contiguous width where status items can render inline. On a notched
    /// display, macOS won't move expanded items left of the notch (#924).
    static func usableInlineWidth(
        from appMenuRightEdge: CGFloat?,
        screenFrameMinX: CGFloat,
        screenVisibleMaxX: CGFloat,
        notchFrame: CGRect?
    ) -> CGFloat {
        let clampedAppMenuRightEdge = max(screenFrameMinX, appMenuRightEdge ?? screenFrameMinX)

        if let notchFrame {
            let usableRightOfNotchStart = notchFrame.maxX + notchGap
            return max(0, screenVisibleMaxX - usableRightOfNotchStart)
        }

        return max(0, screenVisibleMaxX - clampedAppMenuRightEdge)
    }

    /// Hiding application menus makes Thaw a regular app, which flashes the
    /// Dock icon, so the keep-Dock-clean setting disables it.
    static func allowsHidingApplicationMenus(
        hideApplicationMenus: Bool,
        hideDockIconWhenToggling: Bool
    ) -> Bool {
        hideApplicationMenus && !hideDockIconWhenToggling
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
