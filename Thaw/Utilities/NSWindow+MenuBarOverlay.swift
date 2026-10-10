//
//  NSWindow+MenuBarOverlay.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import AppKit
import MenuBarModel

extension NSWindow {
    /// Nil without a positive backing window number; converting a negative number to unsigned CGWindowID traps.
    var windowServerID: CGWindowID? {
        windowNumber > 0 ? CGWindowID(windowNumber) : nil
    }

    /// Register when ordered in so MenuOpenMonitor does not mistake Thaw's overlay for an open menu.
    func registerAsMenuBarOverlay() {
        guard let windowServerID else { return }
        MenuBarOverlayWindows.register(windowServerID)
    }

    /// Call when the window is ordered out. Window numbers are recycled, so a
    /// registration left behind would silence a real menu that reuses the ID.
    func unregisterAsMenuBarOverlay() {
        guard let windowServerID else { return }
        MenuBarOverlayWindows.unregister(windowServerID)
    }
}

extension NSPanel {
    /// Sits above the menu bar on every Space without stealing focus or appearing in Thaw's captures.
    /// absorbsClicks controls whether clicks pass through to the bar.
    static func menuBarOverlay(opaque: Bool, absorbsClicks: Bool) -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.isOpaque = opaque
        if !opaque {
            panel.backgroundColor = .clear
        }
        panel.hasShadow = false
        panel.level = .mainMenu + 1
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .canJoinAllSpaces, .stationary]
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.ignoresMouseEvents = !absorbsClicks
        panel.sharingType = .none
        return panel
    }
}
