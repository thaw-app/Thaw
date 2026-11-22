//
//  ReducedModeOfferButton.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Lets someone who will not grant Accessibility still hide whole apps.
struct ReducedModeOfferButton: View {
    @Environment(AppState.self) private var appState
    /// Previews pass their own, so the choice doesn't start the app.
    var choose: (() -> Void)?

    static let consequence: LocalizedStringResource =
        "You can hide whole apps from a menu. Arranging items, the \(Constants.displayName) Bar and search stay off."

    /// The consequence as the permissions window words it, above this button.
    static let offer: LocalizedStringResource =
        "Without Accessibility, you can still hide whole apps from a menu. Arranging items, the \(Constants.displayName) Bar and search stay off."

    var body: some View {
        Button("Continue without Accessibility") {
            if let choose {
                choose()
                return
            }
            ReducedModeController.isChosen = true
            appState.finishAccessRecovery()
        }
        .help(Text(Self.consequence))
    }
}
