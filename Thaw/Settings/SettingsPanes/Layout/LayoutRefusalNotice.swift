//
//  LayoutRefusalNotice.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Why a layout change snapped back, shown in the pane rather than a modal that would cover the bars.
struct LayoutRefusalNotice: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let refusal = appState.layoutFeedback.refusal {
            VStack(alignment: .leading, spacing: ThawSpacing.inset) {
                if refusal.isAboutSystemItems {
                    Text("macOS 27 does not let \(Constants.displayName) hide some system items.")
                        .font(ThawType.footnote)
                        .foregroundStyle(ThawInk.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SettingsWarningPill(
                    title: LocalizedStringResource(String.LocalizationValue(refusal.title)),
                    message: LocalizedStringResource(String.LocalizationValue(refusal.message)),
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange,
                    actionTitle: "Dismiss",
                    action: appState.layoutFeedback.clear
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.fade(reduceMotion: reduceMotion, animation: ThawMotion.settle))
        }
    }
}
