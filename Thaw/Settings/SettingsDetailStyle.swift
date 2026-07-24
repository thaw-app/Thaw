//
//  SettingsDetailStyle.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - SettingsDetailLayout

enum SettingsDetailLayout {
    /// Comfortable reading width for settings groups. Title and form share this
    /// column so they stay aligned when the window grows.
    static let columnMaxWidth: CGFloat = 680
    /// Offset from the window top under the transparent unified toolbar.
    /// Intentionally well below the ~60pt safe-area push.
    static let titleTopInset: CGFloat = 28
    /// Leading inset aligned with grouped form section cards / headers.
    static let titleHorizontalInset: CGFloat = 28
}

extension EnvironmentValues {
    @Entry var settingsPaneTitle: LocalizedStringKey?
}

// MARK: - SettingsGlassButtonStyle

struct SettingsGlassButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            configuration.trigger()
        } label: {
            configuration.label
                .padding(.horizontal, 16)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 16))
    }
}

extension PrimitiveButtonStyle where Self == SettingsGlassButtonStyle {
    static var settingsGlass: SettingsGlassButtonStyle {
        .init()
    }
}
