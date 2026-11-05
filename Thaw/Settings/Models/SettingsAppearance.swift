//
//  SettingsAppearance.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
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
    func windowAppearance(macOSIsDark: Bool) -> SettingsWindowAppearance {
        colorScheme(macOSIsDark: macOSIsDark) == .dark ? .dark : .light
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
