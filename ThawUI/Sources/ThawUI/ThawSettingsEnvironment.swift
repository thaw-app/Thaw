//
//  ThawSettingsEnvironment.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

extension EnvironmentValues {
    /// Whether explanatory captions below settings rows are shown. True by default so surfaces
    /// outside the settings window keep their captions regardless of the preference.
    @Entry public var settingsDescriptionsVisible: Bool = true

    /// A title a ThawForm draws over itself; hosts like the What's New window set it.
    @Entry public var settingsPaneTitle: LocalizedStringResource?

    /// Set for a search field that is its own piece of glass: it draws no glass and marks focus on this outline.
    @Entry public var fieldPieceOutline: RoundedRectangle?
}

public enum SettingsDetailLayout {
    /// Comfortable reading width for settings groups. Title and form share this
    /// column so they stay aligned when the window grows.
    public static let columnMaxWidth: CGFloat = 748
    /// Offset from the window top under the transparent unified toolbar, well below the ~60pt safe-area push.
    public static let titleTopInset: CGFloat = 28

    /// Leading inset aligned with grouped form section cards / headers.
    public static let titleHorizontalInset: CGFloat = 28
}
