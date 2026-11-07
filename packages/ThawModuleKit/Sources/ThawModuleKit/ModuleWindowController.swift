//
//  ModuleWindowController.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

/// The one window a module app shows when the user opens it. The window is
/// built the first time it is shown and kept, not released, when closed.
@MainActor
public final class ModuleWindowController {
    /// Whether Thaw launched the module to show its window right away.
    public static var isRequestedAtLaunch: Bool {
        CommandLine.arguments.contains(ModuleLaunchEnvironment.showWindowArgument)
    }

    private let makeWindow: () -> NSWindow
    private var window: NSWindow?

    public init(
        title: String,
        styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable],
        content: @escaping () -> some View
    ) {
        makeWindow = { Self.makeWindow(title: title, styleMask: styleMask, content: content) }
    }

    /// A scrolling form reports no preferred size, so the window is sized from the view's fitting size instead.
    static func makeWindow(title: String, styleMask: NSWindow.StyleMask, content: () -> some View) -> NSWindow {
        let controller = NSHostingController(rootView: content())
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = styleMask
        window.isReleasedWhenClosed = false
        let visibleHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        window.setContentSize(contentSize(fitting: controller.view.fittingSize, visibleHeight: visibleHeight))
        window.center()
        return window
    }

    /// The content's fitting size, at most 80% of the screen's height; the form scrolls for the rest.
    static func contentSize(fitting: CGSize, visibleHeight: CGFloat) -> CGSize {
        CGSize(width: fitting.width, height: min(fitting.height, (visibleHeight * 0.8).rounded()))
    }

    /// Brings the window to the front, activating the module.
    public func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
