//
//  HIDEventManager+HoverThawIcon.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

extension HIDEventManager {
    /// Hover and click state for Thaw's icon. Static so ControlItem can read it;
    /// the app has one HIDEventManager.
    static var thawIconHoverGate = ThawIconHoverGate()

    /// Whether hover may reveal the hidden section here: empty menu bar space,
    /// or Thaw's shown icon while no press has latched it.
    func isMouseOnHoverRevealSpot(appState: AppState, screen: NSScreen) -> Bool {
        if isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen) {
            return true
        }
        return Self.thawIconHoverGate.mayArmFromIcon
            && isMouseInsideMenuBar(appState: appState, screen: screen)
            && !isMouseInsideNotch(appState: appState, screen: screen)
            && isMouseOnShownThawIcon(appState: appState)
    }

    /// Whether the pointer is over Thaw's icon, not the collapsed stand-in left
    /// while the icon is turned off.
    private func isMouseOnShownThawIcon(appState: AppState) -> Bool {
        guard let iconWindow = appState.menuBarManager.section(withName: .visible)?.controlItem.window else {
            return false
        }
        return ThawIconHoverGate.isHoverTarget(
            showsIcon: configuration.showThawIcon,
            iconWidth: iconWindow.frame.width
        ) && isMouseInsideThawIcon(appState: appState)
    }

    /// Lets the icon arm a hover reveal again once the pointer has left it.
    func releaseThawIconHoverLatchIfPointerLeft(appState: AppState) {
        guard Self.thawIconHoverGate.isLatched else {
            return
        }
        Self.thawIconHoverGate.notePointer(onIcon: isMouseOnShownThawIcon(appState: appState))
    }

    /// Records a press for the icon's hover. A press soon after a hover reveal
    /// hands the reveal to the click, which keeps it open for the full rehide interval.
    func noteThawIconPress(appState: AppState) {
        let adopts = Self.thawIconHoverGate.notePress(
            onIcon: isMouseOnShownThawIcon(appState: appState),
            isHoverReveal: isHoverReveal,
            at: .now
        )
        guard adopts else {
            return
        }
        Self.diagLog.debug("hover: a click on the Thaw icon keeps the section hover just revealed")
        isHoverReveal = false
    }
}

extension ControlItem {
    /// Whether this click on Thaw's icon leaves section open because hover just revealed it.
    func keepsHoverRevealOpen(_ section: MenuBarSection) -> Bool {
        guard identifier == .visible else {
            return false
        }
        return HIDEventManager.thawIconHoverGate.claimClick(at: .now) && !section.isHidden
    }
}
