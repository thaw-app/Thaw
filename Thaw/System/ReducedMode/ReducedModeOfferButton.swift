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

    var body: some View {
        Button {
            ReducedModeController.isChosen = true
            appState.completeFirstLaunchSetup()
        } label: {
            Text("Continue without Accessibility")
                .font(ThawType.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Hide whole apps from a menu. Arranging items, the \(Constants.displayName) Bar and search stay off.")
        .padding(.trailing, ThawSpacing.gutter)
        .padding(.bottom, ThawSpacing.inset)
    }
}
