//
//  WhatsNewWindow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The standalone, resizable What's New window. Kept separate from Settings so
/// release notes read as their own destination, reachable from the menu, the
/// About pane, and automatically on the first launch after an upgrade.
struct WhatsNewWindow: Scene {
    @Bindable var appState: AppState

    var body: some Scene {
        ThawWindow(id: .whatsNew, appState: appState) {
            WhatsNewPage(appState: appState)
                .environment(appState)
                // The update's notes are shown once; opened again later, the
                // window starts on the newest release like any other time.
                .onDisappear { appState.pendingUpdateVersion = nil }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 860, height: 780)
        .windowStyle(.titleBar)
    }
}

/// A view of its own so the page follows the Privacy switch and a pending
/// update while the window is open.
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
