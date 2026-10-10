//
//  HIDEventManager+SecondaryContextMenu.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import AppKit
import Foundation
import MenuBarModel

extension HIDEventManager {
    // MARK: Handle Secondary Context Menu

    /// Returns whether macOS 27 should route a secondary click to the Thaw
    /// control item's menu instead of the empty-menu-bar context menu.
    static nonisolated func shouldShowControlItemContextMenu(
        usesMenuBarAgent: Bool,
        controlItemFrame: CGRect?,
        clickLocation: CGPoint
    ) -> Bool {
        guard usesMenuBarAgent, let frame = controlItemFrame else {
            return false
        }
        // macOS 27 control frames can lag reflow or AX refresh; tolerate stale bounds on each edge.
        let tolerance: CGFloat = 10
        let padded = frame.insetBy(dx: -tolerance, dy: -tolerance)
        return padded.contains(clickLocation)
    }

    /// Consumes a press on the icon without opening its menu until the matching release.
    func armControlItemContextMenu(
        appState: AppState,
        clickLocation: CGPoint
    ) -> Bool {
        guard
            let controlItem = appState.menuBarManager.section(withName: .visible)?.controlItem,
            pressLandsOnControlItem(controlItem, appState: appState, clickLocation: clickLocation)
        else {
            return false
        }
        pendingControlItemContextMenu = (controlItem, clickLocation)
        return true
    }

    /// Raises the menu a press armed, but only if the pointer is still on the
    /// icon, so a press that turned into a drag does not open it.
    func flushPendingControlItemContextMenu() {
        guard let pending = pendingControlItemContextMenu else {
            return
        }
        pendingControlItemContextMenu = nil
        let releaseLocation = NSEvent.mouseLocation
        guard
            let appState,
            pressLandsOnControlItem(pending.item, appState: appState, clickLocation: releaseLocation)
        else {
            return
        }
        pending.item.showContextMenu(at: releaseLocation)
    }

    /// Whether the press is on the Thaw icon on the display under the pointer.
    /// The status item window sits on one display; macOS 27 draws the icon on all of them.
    func pressLandsOnControlItem(
        _ controlItem: ControlItem,
        appState: AppState,
        clickLocation: CGPoint
    ) -> Bool {
        if let liveFrame = controlItemContextMenuFrame(of: controlItem),
           isUsableControlItemFrame(liveFrame)
        {
            // Do not store AppKit frames as the fullscreen fallback; it uses Core Graphics pointers and cached bounds.
            if Self.shouldShowControlItemContextMenu(
                usesMenuBarAgent: true,
                controlItemFrame: liveFrame,
                clickLocation: clickLocation
            ) {
                return true
            }
        }
        // AX bounds are Core Graphics rects, so the pointer is re-read in that space.
        guard let pointerLocation = MouseHelpers.locationCoreGraphics else {
            return false
        }
        if Self.shouldShowControlItemContextMenu(
            usesMenuBarAgent: true,
            controlItemFrame: visibleControlItemAXFrame(appState: appState, under: pointerLocation),
            clickLocation: pointerLocation
        ) {
            return true
        }
        // A fullscreen space reports no usable live window frame; the managed
        // list's last known icon bounds keep the right click working.
        let fallback = lastKnownVisibleControlItemBounds(appState: appState)
        let matches = Self.shouldShowControlItemContextMenu(
            usesMenuBarAgent: true,
            controlItemFrame: fallback,
            clickLocation: pointerLocation
        )
        if !matches {
            Self.diagLog.debug(
                "control item right-click missed: live=\(String(describing: controlItemContextMenuFrame(of: controlItem))) fallback=\(String(describing: fallback)) pointer=\(pointerLocation)"
            )
        }
        return matches
    }

    /// Whether a live control item frame is a real on-screen rect, rather than
    /// the missing or off-screen frame a fullscreen space reports.
    private func isUsableControlItemFrame(_ frame: CGRect) -> Bool {
        guard frame.width > 0, frame.height > 0 else {
            return false
        }
        return NSScreen.screens.contains { $0.frame.intersects(frame) }
    }

    /// Remembers the Thaw icon's on-screen rect while the bar is visible, so
    /// the fullscreen fallback has a seat even after a cold launch.
    func rememberVisibleControlItemBounds(in cache: MenuBarItemManager.ItemCache) {
        guard
            let bounds = cache.managedItems.first(where: { $0.tag.matchesVisibleControlItem })?.bounds,
            isUsableControlItemFrame(bounds)
        else {
            return
        }
        lastUsableVisibleControlItemBounds = bounds
    }

    /// The visible control item's last known bounds, in Core Graphics space,
    /// for when no live frame is usable. Only on-screen rects are remembered.
    private func lastKnownVisibleControlItemBounds(appState: AppState) -> CGRect? {
        let bounds = appState.itemManager.managedItems.first { item in
            item.tag.matchesVisibleControlItem
                && item.bounds.width > 0
                && item.bounds.height > 0
        }?.bounds
        if let bounds, isUsableControlItemFrame(bounds) {
            lastUsableVisibleControlItemBounds = bounds
        }
        return lastUsableVisibleControlItemBounds
    }

    /// The icon's live frame, preferring the window over the last-reported
    /// AppKit frame over the on-screen approximation.
    private func controlItemContextMenuFrame(of controlItem: ControlItem) -> CGRect? {
        controlItem.window?.frame
            ?? controlItem.frame
            ?? controlItem.onScreenFrame
    }

    /// AX bounds in Core Graphics space on the pointer's display.
    /// Prefer the last walk, which covers every display, over the active-display-only managed cache.
    private func visibleControlItemAXFrame(
        appState: AppState,
        under pointerLocation: CGPoint
    ) -> CGRect? {
        guard let pointerDisplayID = Self.displayID(containing: pointerLocation, fallback: nil) else {
            return nil
        }
        let displayBounds = CGDisplayBounds(pointerDisplayID)
        let itemManager = appState.itemManager
        let candidates = itemManager.onScreenItemSnapshot.items + itemManager.managedItems
        let controlItems = candidates.filter { item in
            item.tag.matchesVisibleControlItem
                && item.bounds.width > 0
                && item.bounds.height > 0
        }
        if let onThisDisplay = controlItems.first(where: {
            MenuBarItemAXProvider.frame($0.bounds, isWithin: displayBounds)
        }) {
            return onThisDisplay.bounds
        }
        // macOS 27 draws the icon on every bar but reports one display's geometry.
        // Rebase the reported frame onto the mirrored bar under the pointer.
        guard let reported = controlItems.first,
              let reportedDisplay = Self.displayBounds(containing: reported.bounds)
        else {
            return nil
        }
        return MirroredBarGeometry.rebasedFrame(
            reported.bounds,
            from: reportedDisplay,
            to: displayBounds
        )
    }

    /// The active display whose bounds contain frame's centre, if any.
    private static func displayBounds(containing frame: CGRect) -> CGRect? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return nil }
        for index in 0 ..< Int(count) {
            let bounds = CGDisplayBounds(ids[index])
            if bounds.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                return bounds
            }
        }
        return nil
    }

    func handleSecondaryContextMenu(
        appState: AppState,
        screen: NSScreen
    ) {
        pendingSecondaryContextMenuTask = Task { [weak self] in
            guard let self else { return }
            // Suppress phantom clicks in an auto-hidden fullscreen bar's y-band.
            // The event still reaches the underlying app's native context menu.
            if !screen.isSystemMenuBarVisible() {
                Self.diagLog.debug("handleSecondaryContextMenu: suppressing, no menu bar items on-screen for active space")
                return
            }
            guard configuration.enableSecondaryContextMenu else {
                return
            }
            guard
                isMouseInsideEmptyMenuBarSpace(
                    appState: appState,
                    screen: screen
                )
            else {
                return
            }
            guard let mouseLocation = MouseHelpers.locationAppKit else {
                return
            }
            // Delay prevents immediate closure and lets a foreign widget's menu render.
            // Probe open menus rather than wide notch-overlay bounds, since only their icons respond to clicks.
            try await Task.sleep(for: .milliseconds(100))
            try Task.checkCancellation()
            if isForeignPopUpMenuOpen() {
                Self.diagLog.debug("handleSecondaryContextMenu: suppressing, foreign pop-up menu is open")
                return
            }
            if await isCursorOverForeignWidgetUIElementFresh() {
                Self.diagLog.debug("handleSecondaryContextMenu: suppressing, cursor over foreign UI element")
                return
            }
            appState.menuBarManager.showSecondaryContextMenu(at: mouseLocation)
        }
    }

    /// AX hit-test excluding Thaw, Window Server backgrounds, and menu-bar/menu/menu-item roles from the front app.
    /// Defer to foreign widgets under the cursor even when they do not open a pop-up menu.
    func isCursorOverForeignWidgetUIElement() -> Bool {
        guard let mouseLocation = MouseHelpers.locationCoreGraphics else {
            return false
        }
        // Event taps cannot wait on AX; unknown counts as no widget and starts a read for the next event.
        return pointerAXCache.foreignWidget(at: mouseLocation) ?? false
    }

    /// The same question answered fresh, for paths that already wait.
    func isCursorOverForeignWidgetUIElementFresh() async -> Bool {
        guard let mouseLocation = MouseHelpers.locationCoreGraphics else {
            return false
        }
        return await pointerAXCache.isForeignWidget(at: mouseLocation)
    }

    /// Exact kCGPopUpMenuWindowLevel filtering distinguishes foreign menus from idle notch overlays one level below.
    /// Avoid showing Thaw's context menu over a foreign widget's own menu.
    private func isForeignPopUpMenuOpen() -> Bool {
        WindowLevelPredicates.isForeignPopUpMenuOpen(in: WindowInfo.createWindows(option: .onScreen))
    }
}
