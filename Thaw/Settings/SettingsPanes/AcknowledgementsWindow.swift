//
//  AcknowledgementsWindow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

/// A ReadingPage like What's New. A window, so it can carry the same glass and the same path along the top.
@MainActor
enum AcknowledgementsWindow {
    static let defaultSize = CGSize(width: 860, height: 780)

    static func makeWindow(appState: AppState, delegate: NSWindowDelegate?) -> NSWindow {
        let rootView = ThawWindowConfiguration.configuredContent(
            AcknowledgementsView(appName: Constants.displayName, strings: .thaw, content: .thaw)
                .environment(appState)
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        ThawWindowConfiguration.configureCommon(window, id: .acknowledgements)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isOpaque = false
        window.backgroundColor = .clear

        let controller = NSHostingController(rootView: rootView)
        controller.sizingOptions = [.minSize]
        window.contentViewController = controller
        window.setContentSize(defaultSize)
        window.center()
        window.delegate = delegate
        return window
    }
}
