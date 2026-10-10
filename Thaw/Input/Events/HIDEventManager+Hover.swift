//
//  HIDEventManager+Hover.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import AppKit
import Foundation
import MenuBarModel

extension HIDEventManager {
    enum HoverAction {
        case show
        case hide
    }

    /// Short hide delay after leaving the menu bar and Thaw Bar; an open menu still retains the reveal.
    /// Using the longer rehide interval lets repeated pointer brushes keep hover reveals open.
    static let hoverRevealHideDelay: TimeInterval = 1

    /// The latch blocks reveals after explicit clicks or hotkeys, but not conceal-on-leave.
    /// Concealing resets the latch for the next hover cycle.
    static nonisolated func shouldProcessHover(
        showOnHover: Bool,
        showOnHoverAllowed: Bool,
        sectionIsHidden: Bool
    ) -> Bool {
        showOnHover && (!sectionIsHidden || showOnHoverAllowed)
    }

    private func isMouseNearMenuBar(screen: NSScreen, verticalPadding: CGFloat = 80) -> Bool {
        guard
            let mouseLocation = MouseHelpers.locationAppKit,
            let menuBarHeight = screen.getMenuBarHeight()
        else {
            return false
        }

        return mouseLocation.x >= screen.frame.minX
            && mouseLocation.x <= screen.frame.maxX
            && mouseLocation.y <= screen.frame.maxY
            && mouseLocation.y >= screen.frame.maxY - menuBarHeight - verticalPadding
    }

    func scheduleHoverRearmChecks(appState: AppState) {
        let taskToken = UUID()
        hoverRearmTaskToken = taskToken
        hoverRearmTask = Task { @MainActor [weak self, weak appState] in
            guard let self, let appState else {
                return
            }

            defer {
                if hoverRearmTaskToken == taskToken {
                    hoverRearmTask = nil
                    hoverRearmTaskToken = nil
                }
            }

            for attempt in 0 ..< 12 {
                do {
                    try await Task.sleep(for: attempt == 0 ? .milliseconds(50) : .milliseconds(200))
                } catch {
                    return
                }

                guard
                    hoverRearmTaskToken == taskToken,
                    isEnabled,
                    configuration.showOnHover,
                    appState.menuBarManager.showOnHoverAllowed
                else {
                    return
                }

                if needsMouseMovedTap(appState: appState) {
                    _ = mouseMovedTap.ensureValid()
                    mouseMovedTap.start()
                }

                guard let screen = NSScreen.screenWithMouse ?? bestScreen(appState: appState) else {
                    continue
                }

                guard isMouseNearMenuBar(screen: screen) else {
                    return
                }

                handleShowOnHover(appState: appState, screen: screen)

                if pendingHoverAction == .show ||
                    !(appState.menuBarManager.section(withName: .hidden)?.isHidden ?? true)
                {
                    return
                }
            }
        }
    }

    // MARK: Handle Show On Hover

    /// Cancel only the specified action when the pointer leaves its arming region, preventing late changes.
    private func cancelPendingHover(_ action: HoverAction) {
        guard pendingHoverAction == action else {
            return
        }
        hoverTask?.cancel()
        hoverTask = nil
        hoverTaskToken = nil
        pendingHoverAction = nil
    }

    /// The token prevents superseded tasks from clearing their replacement's state.
    private func scheduleHover(
        _ action: HoverAction,
        after delay: TimeInterval,
        then body: @escaping @MainActor () async -> Void
    ) {
        hoverTask?.cancel()
        pendingHoverAction = action
        let taskToken = UUID()
        hoverTaskToken = taskToken
        hoverTask = Task {
            defer {
                if hoverTaskToken == taskToken {
                    hoverTask = nil
                    hoverTaskToken = nil
                    if pendingHoverAction == action {
                        pendingHoverAction = nil
                    }
                }
            }
            try await Task.sleep(for: .seconds(delay))
            await body()
        }
    }

    /// Reveal and hide share one pending task so pointer sweeps cannot queue contradictory changes.
    func handleShowOnHover(appState: AppState, screen: NSScreen) {
        // Do not assume the hidden section exists.
        guard
            let hiddenSection = appState.menuBarManager.section(
                withName: .hidden
            )
        else {
            return
        }

        guard Self.shouldProcessHover(
            showOnHover: configuration.showOnHover,
            showOnHoverAllowed: appState.menuBarManager.showOnHoverAllowed,
            sectionIsHidden: hiddenSection.isHidden
        ) else {
            return
        }

        guard hiddenSection.isHidden else {
            armHoverHide(hiddenSection, appState: appState, screen: screen)
            return
        }
        // Whatever revealed the section last, it is closed now.
        isHoverReveal = false
        armHoverShow(hiddenSection, appState: appState, screen: screen)
    }

    /// Arms a reveal while the pointer rests on empty menu bar space that no
    /// foreign widget has claimed, and cancels one otherwise.
    private func armHoverShow(
        _ hiddenSection: MenuBarSection,
        appState: AppState,
        screen: NSScreen
    ) {
        // Pending reveals use geometry to avoid AX walks and foreign-widget hit-tests on every move.
        // The task rechecks items, app menus, and widgets before revealing.
        guard pendingHoverAction != .show else {
            if
                !isMouseInsideMenuBar(appState: appState, screen: screen)
                || isMouseInsideNotch(appState: appState, screen: screen)
            {
                Self.diagLog.debug("hover show: cancelled, the pointer left the menu bar")
                cancelPendingHover(.show)
            }
            return
        }
        guard
            isMouseInsideEmptyMenuBarSpace(
                appState: appState,
                screen: screen
            ),
            !isCursorOverForeignWidgetUIElement()
        else {
            return
        }
        Self.diagLog.debug("hover show: armed for \(configuration.showOnHoverDelay) s")
        scheduleHover(.show, after: configuration.showOnHoverDelay) {
            // Recheck empty space and enabled state, skipped while the reveal was pending.
            guard
                self.isEnabled,
                self.isMouseInsideEmptyMenuBarSpace(
                    appState: appState,
                    screen: screen
                )
            else {
                Self.diagLog.debug("hover show: skipped, the pointer is no longer over empty menu bar space")
                return
            }
            // A fresh read after the cached arm keeps hung-widget delays off the event taps.
            guard await !(self.isCursorOverForeignWidgetUIElementFresh()),
                  !Task.isCancelled,
                  self.isEnabled
            else {
                Self.diagLog.debug("hover show: skipped, the pointer is over another app's widget")
                return
            }
            self.cancelSmartRehide()
            Self.diagLog.debug("hover show: revealing")
            hiddenSection.show()
            self.isHoverReveal = true
        }
    }

    /// Arms a hide once the pointer has left both the retention band under the
    /// menu bar and the Thaw Bar, and cancels one otherwise.
    private func armHoverHide(
        _ hiddenSection: MenuBarSection,
        appState: AppState,
        screen: NSScreen
    ) {
        guard
            !isMouseInsideMenuBarHoverBand(appState: appState, screen: screen),
            !isMouseInsideThawBar(appState: appState)
        else {
            if pendingHoverAction == .hide {
                Self.diagLog.debug("hover hide: cancelled, the pointer is back on the menu bar or the Thaw Bar")
            }
            cancelPendingHover(.hide)
            return
        }
        // With auto-rehide off, leave the section open until an explicit close action.
        guard configuration.autoRehide else {
            if pendingHoverAction == .hide {
                Self.diagLog.debug("hover hide: not armed, Hide automatically is off")
            }
            cancelPendingHover(.hide)
            return
        }
        guard pendingHoverAction != .hide else {
            return
        }
        // Hover reveals close quickly after leaving both bars; clicks and hotkeys use the user's rehide interval.
        let delay = isHoverReveal ? Self.hoverRevealHideDelay : configuration.rehideInterval
        Self.diagLog.debug("hover hide: armed for \(delay) s (\(isHoverReveal ? "hover reveal" : "rehide interval"))")
        scheduleHover(.hide, after: delay) {
            // Recheck settings and the retention band; cursor tremor at the bar edge must not trigger a reveal-hide loop.
            guard
                self.isEnabled,
                self.configuration.autoRehide,
                !self.isMouseInsideMenuBarHoverBand(appState: appState, screen: screen),
                !self.isMouseInsideThawBar(appState: appState)
            else {
                Self.diagLog.debug("hover hide: skipped, the pointer came back or the setting changed")
                return
            }
            // Don't hide while the user is interacting with an open menu.
            if await self.menuOpenMonitor?.isAnyMenuOpen() == true {
                Self.diagLog.debug("hover hide: skipped, a menu is open")
                return
            }
            // The await can allow newer pointer events to rearm or cancel this hide; recheck before hiding.
            guard
                !Task.isCancelled,
                self.isEnabled,
                self.configuration.autoRehide,
                !self.isMouseInsideMenuBarHoverBand(appState: appState, screen: screen),
                !self.isMouseInsideThawBar(appState: appState)
            else {
                return
            }
            Self.diagLog.debug("hover hide: hiding")
            self.isHoverReveal = false
            hiddenSection.hide()
        }
    }

    // MARK: Handle Prevent Show On Hover

    /// Suppresses show-on-hover after a press in the menu bar, until the
    /// pointer leaves and hovering is allowed again.
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

    /// Empty-space presses suppress hover; item presses do so when a section is revealed or Thaw's icon is pressed.
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
            ) != true
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

    // MARK: Handle Show On Scroll

    /// Reveals or puts away the hidden section when the user scrolls over
    /// empty menu bar space, following the direction of the gesture.
    func handleShowOnScroll(
        with event: NSEvent,
        appState: AppState,
        screen: NSScreen
    ) {
        guard
            configuration.showOnScroll,
            isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen),
            !isCursorOverForeignWidgetUIElement(),
            let hiddenSection = appState.menuBarManager.section(
                withName: .hidden
            )
        else {
            return
        }

        // Average axes to handle trackpads and wheels consistently; ignore small, unintentional flicks.
        let threshold: CGFloat = 5
        let delta = (event.scrollingDeltaX + event.scrollingDeltaY) / 2
        if delta > threshold {
            cancelSmartRehide()
            hiddenSection.show()
        } else if delta < -threshold {
            hiddenSection.hide()
        }
    }
}
