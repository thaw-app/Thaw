//
//  HIDEventManager+PointerGeometry.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import AppKit
import Foundation
import MenuBarModel

extension HIDEventManager {
    /// The screen owning the active menu bar, for hover, scroll and tooltips,
    /// so nothing reveals on an inactive bar where clicks would do nothing.
    /// Mouse-down uses NSScreen.screenWithMouse instead.
    func bestScreen(appState _: AppState) -> NSScreen? {
        NSScreen.screenWithActiveMenuBar ?? NSScreen.main
    }

    // MARK: Mouse Location Helpers

    /// Whether the pointer is over screen's menu bar strip.
    func isMouseInsideMenuBar(appState _: AppState, screen: NSScreen) -> Bool {
        guard
            let mouseLocation = MouseHelpers.locationAppKit,
            let menuBarHeight = screen.getMenuBarHeight()
        else {
            return false
        }

        return mouseLocation.x >= screen.frame.minX
            && mouseLocation.x <= screen.frame.maxX
            && mouseLocation.y <= screen.frame.maxY
            && mouseLocation.y >= screen.frame.maxY - menuBarHeight
    }

    /// The menu bar plus hoverRetentionPadding below it. Only the hide side of
    /// show-on-hover and the rehide check use it, so pointer tremor at the bar
    /// edge cannot start a show/hide loop; showing uses isMouseInsideMenuBar.
    func isMouseInsideMenuBarHoverBand(appState _: AppState, screen: NSScreen) -> Bool {
        guard
            let mouseLocation = MouseHelpers.locationAppKit,
            let menuBarHeight = screen.getMenuBarHeight()
        else {
            return false
        }

        let padding = Constants.MenuBarTuning.hoverRetentionPadding
        return mouseLocation.x >= screen.frame.minX
            && mouseLocation.x <= screen.frame.maxX
            && mouseLocation.y <= screen.frame.maxY
            && mouseLocation.y >= screen.frame.maxY - menuBarHeight - padding
    }

    /// Whether the pointer is over the frontmost app's menu, counting the
    /// Apple menu at the far left but stopping short of the notch.
    func isMouseInsideApplicationMenu(appState _: AppState, screen: NSScreen)
        -> Bool
    {
        guard
            let mouseLocation = MouseHelpers.locationCoreGraphics,
            let menuFrame = screen.getApplicationMenuFrame()
        else {
            return false
        }
        var region = menuFrame
        // Extend the frame left to the screen edge to cover the Apple menu.
        region.origin.x = screen.frame.origin.x
        region.size.width = menuFrame.maxX - region.origin.x
        // Cap the right edge at the notch.
        if let notch = screen.frameOfNotch {
            region.size.width = min(region.maxX, notch.minX) - region.origin.x
        }
        return region.contains(mouseLocation)
    }

    /// The bounds of the display under location and of every active display, for rebasing the
    /// frames macOS 27 reports against one bar's layout, and where that display's item lane starts
    /// (see MirroredBarGeometry.drawnFrame). AX shows only the active bar's chevron, so the notch stands in.
    private static func displayContext(
        for location: CGPoint
    ) -> (destination: CGRect?, all: [CGRect], laneMinX: CGFloat?) {
        let all = NSScreen.allDisplayBoundsCG
        guard let screen = NSScreen.screen(containingCGPoint: location) else {
            return (nil, all, nil)
        }
        let laneMinX = MenuBarItemAXProvider.nativeOverflowControlBounds(on: screen.displayID).map(\.minX).min()
            ?? screen.frameOfNotch?.maxX
        return (CGDisplayBounds(screen.displayID), all, laneMinX)
    }

    /// The fast path for hover and click hit-testing.
    private func isMouseInsideCachedMenuBarItem() -> Bool {
        guard let mouseLocation = MouseHelpers.locationCoreGraphics else {
            return false
        }

        let entries = windowBoundsLock.withLock { $0 }
        let context = Self.displayContext(for: mouseLocation)
        let trustCachedBounds = true
        return Self.menuBarBoundsLookupContains(
            mouseLocation,
            entries: entries,
            destinationDisplay: context.destination,
            displayBounds: context.all,
            laneMinX: context.laneMinX,
            trustCachedBoundsWithoutLiveWindowVerification: trustCachedBounds
        )
    }

    /// macOS 27 fallback when the bounds lookup table is empty or stale.
    private func isMouseInsideManagedItemBounds(
        appState: AppState,
        at mouseLocation: CGPoint
    ) -> Bool {
        let controller = appState.menuBarManager.sectionController
        let effectivelyConcealed = controller.effectivelyConcealedIdentifiers
        let context = Self.displayContext(for: mouseLocation)
        return appState.itemManager.managedItems.contains { item in
            guard let bounds = MirroredBarGeometry.drawnFrame(
                item.bounds,
                on: context.destination,
                displayBounds: context.all,
                laneMinX: context.laneMinX
            ), bounds.contains(mouseLocation) else {
                return false
            }
            return Self.shouldIncludeItemInMenuBarBoundsLookup(
                item,
                section: controller.section(for: item),
                effectivelyConcealed: effectivelyConcealed
            )
        }
    }

    /// Whether the pointer is over any menu bar item.
    ///
    /// Tried cheapest first: the prebuilt bounds table, then the managed item
    /// cache, and only as a last resort a live query to the Window Server.
    func isMouseInsideMenuBarItem(appState: AppState, screen _: NSScreen) -> Bool {
        guard let mouseLocation = MouseHelpers.locationCoreGraphics else {
            return false
        }

        if isMouseInsideCachedMenuBarItem() {
            return true
        }

        if isMouseInsideManagedItemBounds(appState: appState, at: mouseLocation) {
            return true
        }

        // Items just shown may not be cached yet.
        let windowIDs = Bridging.getMenuBarWindowList(option: [
            .onScreen, .activeSpace, .itemsOnly,
        ])
        return windowIDs.contains { windowID in
            guard let bounds = Bridging.getWindowBounds(for: windowID) else {
                return false
            }
            guard bounds.width <= Self.maxReasonableItemWidth else {
                return false
            }
            return bounds.contains(mouseLocation)
        }
    }

    /// Whether the pointer is over screen's notch.
    func isMouseInsideNotch(appState _: AppState, screen: NSScreen) -> Bool {
        guard
            let mouseLocation = MouseHelpers.locationAppKit,
            let frameOfNotch = screen.frameOfNotch
        else {
            return false
        }
        // CGRect.contains excludes its max edge, so a pointer at the very top
        // would miss the notch without the extra point.
        var region = frameOfNotch
        region.size.height += 1
        return region.contains(mouseLocation)
    }

    /// Whether the pointer is over menu bar space that belongs to nobody. The
    /// shared guard for show-on-click, hover and scroll, so an item missed here
    /// lets all three fire on top of it.
    func isMouseInsideEmptyMenuBarSpace(appState: AppState, screen: NSScreen)
        -> Bool
    {
        guard
            isMouseInsideMenuBar(appState: appState, screen: screen),
            !isMouseInsideNotch(appState: appState, screen: screen)
        else {
            return false
        }

        let appMenuResult = isMouseInsideApplicationMenuClickRegion(
            appState: appState,
            screen: screen
        )

        // Fall back to geometry when AX is indeterminate, for example when
        // expanded divider windows interfere with the query.
        let isInAppMenu: Bool = if let result = appMenuResult {
            result
        } else {
            isMouseInsideApplicationMenu(appState: appState, screen: screen)
        }

        guard !isInAppMenu,
              !isMouseInsideMenuBarItem(appState: appState, screen: screen),
              !isMouseInsideThawIcon(appState: appState)
        else {
            return false
        }

        // A stale cache can miss a visible icon, letting a click beside it read
        // as empty space; check the same on-screen bounds the reveal reads.
        if let pointerLocation = MouseHelpers.locationCoreGraphics,
           isMouseInsideOnScreenItemBounds(appState: appState, at: pointerLocation)
        {
            return false
        }
        // The chevron is not an item, but a click on it is not empty space either.
        if isMouseInsideNativeOverflowControl(screen: screen) {
            return false
        }
        return true
    }

    /// Reads cached frames only: a live AX walk is too slow for an event tap.
    private func isMouseInsideNativeOverflowControl(screen: NSScreen) -> Bool {
        guard let mouseLocation = MouseHelpers.locationCoreGraphics else { return false }
        return MenuBarItemAXProvider.nativeOverflowControlBounds(on: screen.displayID)
            .contains { $0.contains(mouseLocation) }
    }

    /// Whether location is inside any on-screen item's bounds, using the
    /// same live snapshot and concealment filter the reveal hit-tests read.
    private func isMouseInsideOnScreenItemBounds(appState: AppState, at location: CGPoint) -> Bool {
        let controller = appState.menuBarManager.sectionController
        let effectivelyConcealed = controller.effectivelyConcealedIdentifiers
        let candidates = appState.itemManager.onScreenItemSnapshot.items
            + appState.itemManager.managedItems
        let context = Self.displayContext(for: location)
        return candidates.contains { item in
            guard let bounds = MirroredBarGeometry.drawnFrame(
                item.bounds,
                on: context.destination,
                displayBounds: context.all,
                laneMinX: context.laneMinX
            ), bounds.contains(location) else {
                return false
            }
            return Self.shouldIncludeItemInMenuBarBoundsLookup(
                item,
                section: controller.section(for: item),
                effectivelyConcealed: effectivelyConcealed
            )
        }
    }

    /// The frame is grown first, so drifting slightly off the edge does not count as leaving.
    func isMouseInsideThawBar(appState: AppState) -> Bool {
        guard let mouseLocation = MouseHelpers.locationAppKit else {
            return false
        }
        let forgivingFrame = appState.menuBarManager.thawBarPanel.frame
            .insetBy(dx: -15, dy: -15)
        return forgivingFrame.contains(mouseLocation)
    }

    /// Whether the pointer is over Thaw's own control item.
    func isMouseInsideThawIcon(appState: AppState) -> Bool {
        guard
            let visibleSection = appState.menuBarManager.section(
                withName: .visible
            ),
            // The live window frame: controlItem.frame is debounced and can be
            // stale after the context menu closes, double-firing show/toggle.
            let iconFrame = visibleSection.controlItem.window?.frame,
            let mouseLocation = MouseHelpers.locationAppKit
        else {
            return false
        }
        return iconFrame.contains(mouseLocation)
    }

    /// Whether the cursor is in the app-menu region click-through uses, or nil
    /// when AX is indeterminate.
    func isMouseInsideApplicationMenuClickRegion(
        appState: AppState,
        screen: NSScreen
    ) -> Bool? {
        guard
            isMouseInsideMenuBar(appState: appState, screen: screen),
            let mouseLocation = MouseHelpers.locationCoreGraphics
        else {
            return false
        }

        // Cached frames only, since this runs inside the taps.
        guard
            let frontApp = NSWorkspace.shared.menuBarOwningApplication,
            let frames = pointerAXCache.applicationMenuFrames(for: frontApp.processIdentifier)
        else {
            return nil
        }
        return frames.contains { $0.contains(mouseLocation) }
    }

    private func applicationMenuItemFrame(at mouseLocation: CGPoint) -> CGRect? {
        guard
            let frontApp = NSWorkspace.shared.menuBarOwningApplication,
            let frames = pointerAXCache.applicationMenuFrames(for: frontApp.processIdentifier)
        else {
            return nil
        }
        return frames.first { $0.contains(mouseLocation) }
    }

    // MARK: Handle Application Menu Click-Through

    /// Forwards app-menu clicks that an expanded divider window would swallow,
    /// which happens after a profile change with the Thaw Bar active.
    ///
    /// - Returns: true if the click was on an application menu area, whether
    ///   or not it was forwarded. Callers skip show-on-click then.
    @discardableResult
    func handleApplicationMenuClickThrough(
        appState: AppState,
        screen: NSScreen
    ) -> Bool {
        guard
            isMouseInsideMenuBar(appState: appState, screen: screen),
            let mouseLocation = MouseHelpers.locationCoreGraphics
        else {
            return false
        }

        // Read the frame now; it can vanish once UI closes below.
        guard let initialFrame = applicationMenuItemFrame(at: mouseLocation) else {
            return false
        }

        let hasExpandedDivider = appState.menuBarManager.sections.contains { section in
            section.controlItem.isSectionDivider && section.controlItem.state == .hideSection
        }
        guard hasExpandedDivider else {
            return true
        }

        let expandedWindowCoversClick = Bridging.getMenuBarWindowList(option: [
            .onScreen, .activeSpace, .itemsOnly,
        ]).contains { windowID in
            guard let bounds = Bridging.getWindowBounds(for: windowID) else {
                return false
            }
            return bounds.width > Self.maxReasonableItemWidth && bounds.contains(mouseLocation)
        }
        guard expandedWindowCoversClick else {
            return true
        }

        appState.menuBarManager.thawBarPanel.close()
        for section in appState.menuBarManager.sections {
            section.hide()
        }

        guard let frontApp = NSWorkspace.shared.menuBarOwningApplication else {
            return true
        }

        let frame = initialFrame

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastAppMenuClickTime >= 0.3 else { return true }
        lastAppMenuClickTime = now

        let clickPoint = CGPoint(x: frame.midX, y: frame.midY)
        let pid = frontApp.processIdentifier

        guard let source = CGEventSource(stateID: .hidSystemState) else { return true }
        let mouseDown = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: clickPoint,
            mouseButton: .left
        )
        let mouseUp = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: clickPoint,
            mouseButton: .left
        )
        mouseDown?.postToPid(pid)
        mouseUp?.postToPid(pid)
        return true
    }
}
