//
//  PopoverAnchor.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Gives an NSPopover something to point at where there is no view of Thaw's own.
///
/// NSPopover needs a view, so this parks a one-pixel click-through window at
/// the wanted spot: the top center of a screen, for a surface that hangs from
/// it like a menu, or a status item's frame when AppKit will not let the
/// popover point at the button itself.
///
/// Reused across shows; a fresh anchor each time flickers the popover's arrow.
@MainActor
final class PopoverAnchor {
    /// The screen a summoned surface hangs from when the caller names none.
    ///
    /// The pointer's screen wins over .main: the user expects the surface
    /// where they made the gesture.
    static var defaultScreen: NSScreen? {
        NSScreen.screenWithMouse ?? NSScreen.main
    }

    /// The invisible window the popover points at.
    private var window: NSWindow?

    /// Moves the anchor to the top of screen and returns the view a popover
    /// can be shown relative to.
    func view(atTopOf screen: NSScreen) -> NSView? {
        let frame = screen.visibleFrame
        return view(at: CGPoint(x: frame.midX, y: frame.maxY - 1))
    }

    /// Moves the anchor to origin and returns the view a popover can be shown
    /// relative to.
    func view(at origin: CGPoint) -> NSView? {
        let window = anchorWindow()
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()
        return window.contentView
    }

    /// Takes the anchor off screen once the popover it held is gone.
    func hide() {
        window?.orderOut(nil)
    }

    private func anchorWindow() -> NSWindow {
        if let window {
            return window
        }
        let size = CGSize(width: 1, height: 1)
        let newWindow = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
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
        newWindow.contentView = NSView(frame: CGRect(origin: .zero, size: size))
        window = newWindow
        return newWindow
    }
}
