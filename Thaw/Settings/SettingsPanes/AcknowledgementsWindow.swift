//
//  AcknowledgementsWindow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// A ReadingPage like What's New. A window, so it can carry the same glass and the same path along the top.
struct AcknowledgementsWindow: Scene {
    @Bindable var appState: AppState

    var body: some Scene {
        ThawWindow(id: .acknowledgements, appState: appState) {
            AcknowledgementsView(appName: Constants.displayName, strings: .thaw, content: .thaw)
                .environment(appState)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 860, height: 780)
        .windowStyle(.titleBar)
    }
}
