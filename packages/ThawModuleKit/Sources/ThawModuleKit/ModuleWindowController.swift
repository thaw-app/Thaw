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
        makeWindow = {
            let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
            window.title = title
            window.styleMask = styleMask
            window.isReleasedWhenClosed = false
            window.center()
            return window
        }
    }

    /// Brings the window to the front, activating the module.
    public func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
