//
//  SettingsThemeModifier.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI
import ThawUI

/// Holds a window to the Settings theme. ThawUI and SwiftUI both set a window's look, so both
/// get the same light or dark value, and System is updated when macOS switches.
private struct SettingsThemeModifier: ViewModifier {
    let appearance: SettingsAppearance
    let drawsBackground: Bool
    @State private var macOSIsDark = SystemAppearance.macOS == .dark

    private static let themeChanged = DistributedNotificationCenter.default()
        .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
        .receive(on: DispatchQueue.main)

    func body(content: Content) -> some View {
        let windowAppearance = appearance.windowAppearance(macOSIsDark: macOSIsDark)
        Group {
            if drawsBackground {
                content.settingsWindowBackground(appearance.windowBackground, appearance: windowAppearance)
            } else {
                content.settingsWindowAppearance(windowAppearance)
            }
        }
        .preferredColorScheme(appearance.colorScheme(macOSIsDark: macOSIsDark))
        .onReceive(Self.themeChanged) { _ in
            macOSIsDark = SystemAppearance.macOS == .dark
        }
    }
}

extension View {
    /// Holds the window to the theme. With drawsBackground, Black also draws the window black.
    func settingsTheme(_ appearance: SettingsAppearance, drawsBackground: Bool) -> some View {
        modifier(SettingsThemeModifier(appearance: appearance, drawsBackground: drawsBackground))
    }
}
