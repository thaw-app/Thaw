//
//  ReducedModeOfferButton.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Lets someone who will not grant Accessibility still hide whole apps, saying what stays off before they choose it.
struct ReducedModeOfferButton: View {
    @Environment(AppState.self) private var appState

    static let consequence: LocalizedStringResource =
        "You can hide whole apps from a menu. Arranging items, the \(Constants.displayName) Bar and search stay off."

    var body: some View {
        VStack(alignment: .trailing, spacing: ThawSpacing.hairline) {
            Button("Continue without Accessibility") {
                ReducedModeController.isChosen = true
                appState.completeFirstLaunchSetup()
            }
            .buttonStyle(.link)
            Text(Self.consequence)
                .font(ThawType.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 320, alignment: .trailing)
        .padding(.trailing, ThawSpacing.gutter)
        .padding(.bottom, ThawSpacing.inset)
    }
}
