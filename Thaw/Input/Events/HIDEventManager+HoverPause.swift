//
//  HIDEventManager+HoverPause.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

extension HIDEventManager {
    /// Allows show-on-hover again once the pointer has left the menu bar hover
    /// band, so its next return to the bar can reveal.
    func releaseHoverPauseIfPointerLeft(appState: AppState, screen: NSScreen) {
        let manager = appState.menuBarManager
        guard
            !manager.showOnHoverAllowed,
            HoverPauseLatch.releasesOnPointerMove(
                isPaused: true,
                pointerIsInsideHoverBand: isMouseInsideMenuBarHoverBand(appState: appState, screen: screen),
                isZenModeActive: manager.isZenModeActive
            )
        else {
            return
        }
        manager.showOnHoverAllowed = true
    }

    /// Suppresses show-on-hover after a press in the menu bar, until the
    /// pointer leaves the hover band and hovering is allowed again.
    func handlePreventShowOnHover(
        with event: NSEvent,
        appState: AppState,
        screen: NSScreen
    ) {
        guard
            configuration.showOnHover,
            !appState.menuBarManager.shouldUseThawBar(for: screen.displayID)
        else {
            return
        }

        guard isMouseInsideMenuBar(appState: appState, screen: screen) else {
            return
        }

        guard shouldPreventShowOnHover(for: event, appState: appState, screen: screen) else {
            return
        }

        if appState.menuBarManager.showOnHoverAllowed {
            Self.diagLog.debug("hover: a press in the menu bar pauses it until the pointer leaves")
        }
        appState.menuBarManager.showOnHoverAllowed = false
    }

    /// Empty-space presses suppress hover while the Hidden section is revealed; item presses
    /// do so when a section is revealed or Thaw's icon is pressed.
    private func shouldPreventShowOnHover(
        for event: NSEvent,
        appState: AppState,
        screen: NSScreen
    ) -> Bool {
        guard isMouseInsideMenuBarItem(appState: appState, screen: screen) else {
            // Exclude the frontmost app's menu; indeterminate answers count as empty menu bar space.
            return isMouseInsideApplicationMenuClickRegion(
                appState: appState,
                screen: screen
            ) != true && HoverPauseLatch.pausesOnEmptySpacePress(
                hiddenSectionIsRevealed: appState.menuBarManager.section(withName: .hidden)?.isHidden == false
            )
        }
        switch event.type {
        case .leftMouseDown:
            return appState.menuBarManager.hasVisibleSection
                || isMouseInsideThawIcon(appState: appState)
        case .rightMouseDown:
            return appState.menuBarManager.hasVisibleSection
        default:
            return false
        }
    }
}
