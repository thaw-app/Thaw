//
//  WhatsNewWindow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

/// The standalone, resizable What's New window. Kept separate from Settings so
/// release notes read as their own destination, reachable from the menu, the
/// About pane, and automatically on the first launch after an upgrade.
@MainActor
enum WhatsNewWindow {
    static let defaultSize = CGSize(width: 860, height: 780)

    static func makeWindow(appState: AppState, delegate: NSWindowDelegate?) -> NSWindow {
        let rootView = ThawWindowConfiguration.configuredContent(
            WhatsNewPage(appState: appState)
                .environment(appState)
                // The update's notes are shown once; opened again later, the
                // window starts on the newest release like any other time.
                .onDisappear { appState.pendingUpdateVersion = nil }
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        ThawWindowConfiguration.configureCommon(window, id: .whatsNew)
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

/// A view of its own so the page follows the Privacy switch and a pending update while the window is open.
private struct WhatsNewPage: View {
    let appState: AppState

    var body: some View {
        WhatsNewView(
            info: .thaw,
            strings: .thaw,
            allowFetch: appState.settings.advanced.fetchReleaseNotes,
            pendingUpdateVersion: appState.pendingUpdateVersion
        )
    }
}
