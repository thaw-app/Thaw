//
//  PopoverAnchorWindow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// An invisible window used to anchor a popover to the top of a screen.
@MainActor
final class PopoverAnchorWindow {
    /// Created on first use.
    private var window: NSWindow?

    /// Moves the window to the top center of `screen`, shows it, and
    /// returns its content view to anchor a popover to.
    func anchorView(for screen: NSScreen) -> NSView? {
        let window: NSWindow
        if let existing = self.window {
            window = existing
        } else {
            let newWindow = NSWindow(
                contentRect: .init(origin: .zero, size: .init(width: 1, height: 1)),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.level = .statusBar
            newWindow.ignoresMouseEvents = true
            newWindow.hasShadow = false
            newWindow.contentView = NSView(
                frame: .init(origin: .zero, size: .init(width: 1, height: 1))
            )
            self.window = newWindow
            window = newWindow
        }

        let frame = screen.visibleFrame
        let origin = CGPoint(x: frame.midX, y: frame.maxY - window.frame.height)
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()

        return window.contentView
    }

    /// Hides the window if it was created.
    func orderOut() {
        window?.orderOut(nil)
    }
}
