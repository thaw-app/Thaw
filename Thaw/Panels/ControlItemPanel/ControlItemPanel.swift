//
//  ControlItemPanel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import ThawUI

// MARK: - ControlItemPanelController

/// Replaces the status NSMenu only when enableControlItemPanel is on.
/// macOS 27's zero-height hosted button needs a one-pixel click-through anchor under the icon, as in ScreenTopPopoverAnchor.
@MainActor
final class ControlItemPanelController: NSObject, NSPopoverDelegate {
    private static let diagLog = DiagLog(category: "ControlItemPanel")

    private weak var appState: AppState?
    private var popover: NSPopover?

    /// The invisible window that anchors the popover when the status item's
    /// button cannot.
    private let anchor = PopoverAnchor()

    /// Set when a bounds lookup failed for a window ID, so the next show does
    /// not pay for the same failing lookup before falling back.
    private var staleAnchorWindowID: CGWindowID?

    func performSetup(with appState: AppState) {
        self.appState = appState
    }

    /// Whether the experiment is on. Read live, so the secondary click changes
    /// what it raises without a relaunch.
    var isEnabled: Bool {
        appState?.settings.advanced.enableControlItemPanel ?? false
    }

    var isShown: Bool {
        popover?.isShown ?? false
    }

    /// Prevent reopening on mouse-up after outside mouse-down dismissal, so the icon can close the popover.
    private static let reopenGuard: TimeInterval = 0.35

    /// When an outside press last took the popover down.
    private var lastOutsideDismissal: Date?

    /// Takes the popover down on a press anywhere outside it. Global scope only:
    /// the popover is key while up, so its own clicks are local and never arrive.
    private var dismissMonitor: EventMonitor?

    /// Raises the popover under Thaw's icon, or takes it down if it is already
    /// up, the way a menu does. fallbackPoint is in AppKit screen coordinates.
    func toggle(anchor button: NSStatusBarButton?, fallbackPoint: CGPoint?) {
        if isShown {
            hide()
            return
        }
        if let lastOutsideDismissal,
           Date().timeIntervalSince(lastOutsideDismissal) < Self.reopenGuard
        {
            // The press that opens this gesture is the one that just closed
            // the popover. Swallow the release rather than reopen.
            self.lastOutsideDismissal = nil
            return
        }
        show(anchor: button, fallbackPoint: fallbackPoint)
    }

    func show(anchor button: NSStatusBarButton?, fallbackPoint: CGPoint?) {
        guard let appState else { return }
        hide()

        let popover = makePopover(appState: appState)
        if let button,
           let buttonWindow = button.window,
           buttonWindow.isVisible,
           buttonWindow.frame.height > 0,
           !button.bounds.isEmpty
        {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        } else if let frame = anchorFrame(fallbackPoint: fallbackPoint),
                  let anchorView = anchor.view(at: frame.origin)
        {
            popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        } else {
            Self.diagLog.warning("no anchor for the control item popover; not showing it")
            return
        }

        self.popover = popover
        // The controls have to answer the keyboard, and a popover only becomes
        // key once it is on screen.
        popover.contentViewController?.view.window?.makeKey()
        startDismissMonitor()
    }

    /// Takes the popover down and releases the anchor it was pointing at.
    func hide() {
        dismissMonitor?.stop()
        dismissMonitor = nil
        let closing = popover
        popover = nil
        closing?.performClose(nil)
        anchor.hide()
    }

    // MARK: NSPopoverDelegate

    /// Cleans up after a popover AppKit retired on its own, a transient
    /// dismissal the controller never asked for.
    func popoverDidClose(_ notification: Notification) {
        guard (notification.object as? NSPopover) === popover else {
            return
        }
        dismissMonitor?.stop()
        dismissMonitor = nil
        popover = nil
        anchor.hide()
    }

    // MARK: Placement

    private func anchorScreen(fallbackPoint: CGPoint?) -> NSScreen? {
        if let fallbackPoint,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(fallbackPoint) })
        {
            return screen
        }
        return NSScreen.screenWithMouse ?? NSScreen.main
    }

    /// AppKit coordinates under the bar at the icon's x make the fallback popover hang like a menu.
    private func anchorFrame(fallbackPoint: CGPoint?) -> CGRect? {
        guard let screen = anchorScreen(fallbackPoint: fallbackPoint) else {
            return nil
        }
        let y = screen.frame.maxY - screen.getMenuBarHeightEstimate()
        let x = anchorBounds()?.midX ?? fallbackPoint?.x ?? screen.frame.midX
        return CGRect(x: x, y: y, width: 1, height: 1)
    }

    /// Where Thaw's visible control item sits. Mirrors
    /// ThawBarPanel.controlItemAnchorBounds.
    private func anchorBounds() -> CGRect? {
        guard let item = appState?.itemManager.managedItems.first(matching: .visibleControlItem) else {
            Self.diagLog.warning("no visible control item in the item list; cannot anchor to the icon")
            return nil
        }
        if item.windowID == staleAnchorWindowID {
            return item.bounds.isEmpty ? nil : item.bounds
        }
        if let bounds = Bridging.getWindowBounds(for: item.windowID) {
            staleAnchorWindowID = nil
            return bounds
        }
        staleAnchorWindowID = item.windowID
        return item.bounds.isEmpty ? nil : item.bounds
    }

    private func makePopover(appState: AppState) -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.appearance = NSApp.effectiveAppearance

        let controller = NSHostingController(
            rootView: ControlItemPanelView(appState: appState) { [weak self] in
                self?.hide()
            }
        )
        // Let SwiftUI drive the size: the sections collapse and expand as their
        // state changes, so a fixed size would either clip or leave dead space.
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        return popover
    }

    private func startDismissMonitor() {
        dismissMonitor?.stop()
        dismissMonitor = EventMonitor.startPassive(
            for: [.leftMouseDown, .rightMouseDown],
            scope: .global
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isShown else { return }
                self.lastOutsideDismissal = Date()
                self.hide()
            }
        }
    }
}
