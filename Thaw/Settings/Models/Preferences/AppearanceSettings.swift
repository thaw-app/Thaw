//
//  AppearanceSettings.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Observation

/// Model for the Appearance page's settings that live outside the menu bar look.
@MainActor
@Observable
final class AppearanceSettings: SettingsPageModel {
    /// Whether every display's corners are drawn rounded, like a MacBook's
    /// top corners, with screenCornerRadius.
    var roundScreenCorners = Defaults.DefaultValue.roundScreenCorners {
        didSet {
            guard oldValue != roundScreenCorners else { return }
            Defaults.set(roundScreenCorners, forKey: .roundScreenCorners)
        }
    }

    var screenCornerRadius = Defaults.DefaultValue.screenCornerRadius {
        didSet {
            guard oldValue != screenCornerRadius else { return }
            Defaults.set(screenCornerRadius, forKey: .screenCornerRadius)
        }
    }

    func performSetup() {
        loadInitialState()
    }

    /// Reads the stored values.
    func loadInitialState() {
        Defaults.ifPresent(key: .roundScreenCorners, assign: &roundScreenCorners)
        Defaults.ifPresent(key: .screenCornerRadius, assign: &screenCornerRadius)
    }
}
