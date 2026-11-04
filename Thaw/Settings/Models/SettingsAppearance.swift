//
//  SettingsAppearance.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import SwiftUI
import ThawUI

/// How Thaw draws its own windows: Settings and onboarding. Black is the dark look on pure black,
/// for OLED displays. Anything drawn on or against the menu bar keeps following the menu bar.
nonisolated enum SettingsAppearance: Int, CaseIterable, Identifiable {
    case system = 3
    case light = 0
    case dark = 1
    case black = 2

    var id: Int {
        rawValue
    }

    var localized: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        case .black: "Black"
        }
    }

    /// The name a thaw:// get reports, and the first spelling a set accepts.
    var uriName: String {
        switch self {
        case .system: "system"
        case .light: "light"
        case .dark: "dark"
        case .black: "black"
        }
    }

    /// Light or dark, with System read as what macOS shows now. Never nil: SwiftUI keeps
    /// a previous scheme when asked to follow the system again.
    func colorScheme(macOSIsDark: Bool) -> ColorScheme {
        switch self {
        case .system: macOSIsDark ? .dark : .light
        case .light: .light
        case .dark, .black: .dark
        }
    }

    /// The appearance the window is held to, matching colorScheme(macOSIsDark:).
    func appearanceName(macOSIsDark: Bool) -> NSAppearance.Name {
        colorScheme(macOSIsDark: macOSIsDark) == .dark ? .darkAqua : .aqua
    }

    /// What the settings window draws behind its panes.
    var windowBackground: SettingsWindowBackground {
        self == .black ? .black : .system
    }

    /// Accepts the names "system", "light", "dark" and "black" or their numbers.
    static func fromString(_ value: String) -> SettingsAppearance? {
        if let number = Int(value) {
            return SettingsAppearance(rawValue: number)
        }
        return allCases.first { $0.uriName == value.lowercased() }
    }

    /// The choice before anyone made one: Black for someone who had turned on the old black
    /// background, otherwise System, so no window changes on update.
    static func migrated(legacyBlackBackground: Bool) -> SettingsAppearance {
        legacyBlackBackground ? .black : .system
    }

    /// The choice the old "black background" switch asks for: on is Black, and off turns Black
    /// back into System while leaving the other choices alone.
    func applyingLegacyBlackBackground(_ isBlack: Bool) -> SettingsAppearance {
        if isBlack {
            return .black
        }
        return self == .black ? .system : self
    }
}

@MainActor
extension SettingsAppearance {
    /// Whether macOS itself is in dark mode, from its own setting. A window held to Light or
    /// Dark doesn't change it, unlike the app's effective appearance.
    static var macOSIsDark: Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        return CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication) as? String == "Dark"
    }

    /// The saved choice. The first read, after an update or on a new install, works one out
    /// with migrated(legacyBlackBackground:) and saves it.
    static func stored() -> SettingsAppearance {
        if let rawValue = Defaults.object(forKey: .settingsAppearance) as? Int,
           let saved = SettingsAppearance(rawValue: rawValue)
        {
            return saved
        }
        let chosen = migrated(legacyBlackBackground: Defaults.bool(forKey: .blackSettingsBackground))
        Defaults.set(chosen.rawValue, forKey: .settingsAppearance)
        return chosen
    }
}

extension View {
    /// Holds this view's window to the appearance and draws its background. Settings draws pure
    /// black behind its panes when the choice is Black; other windows only take the appearance.
    func settingsAppearance(_ appearance: SettingsAppearance, drawsBackground: Bool = true) -> some View {
        modifier(SettingsAppearanceModifier(appearance: appearance, drawsBackground: drawsBackground))
    }
}

private struct SettingsAppearanceModifier: ViewModifier {
    let appearance: SettingsAppearance
    let drawsBackground: Bool
    @State private var window: NSWindow?
    @State private var macOSIsDark = SettingsAppearance.macOSIsDark

    private static let themeChanged = DistributedNotificationCenter.default()
        .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
        .receive(on: DispatchQueue.main)

    private var background: SettingsWindowBackground {
        drawsBackground ? appearance.windowBackground : .system
    }

    func body(content: Content) -> some View {
        content
            .background {
                if background == .black {
                    Color.black.ignoresSafeArea()
                }
            }
            // Panes that draw their own backdrop read this, as they would from ThawUI's modifier.
            .environment(\.settingsWindowBackground, background)
            .onWindowChange { window in
                // Use the window handed in: @State written here may not read back until the next update.
                self.window = window
                apply(to: window)
            }
            .onChange(of: appearance) {
                apply(to: window)
            }
            .onChange(of: macOSIsDark) {
                apply(to: window)
            }
            // SwiftUI resets an appearance set on its own windows, so it gets the same value.
            .preferredColorScheme(appearance.colorScheme(macOSIsDark: macOSIsDark))
            .onReceive(Self.themeChanged) { _ in
                macOSIsDark = SettingsAppearance.macOSIsDark
            }
    }

    /// The window's appearance sets the color scheme inside it, sheets included.
    /// Setting the AppKit background too stops a resize flashing another color at the edges.
    private func apply(to window: NSWindow?) {
        guard let window else { return }
        window.appearance = NSAppearance(named: appearance.appearanceName(macOSIsDark: macOSIsDark))
        if drawsBackground {
            window.backgroundColor = background == .black ? .black : .windowBackgroundColor
        }
    }
}
