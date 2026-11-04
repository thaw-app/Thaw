//
//  SystemAppearance.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A value corresponding to a light or dark appearance.
enum SystemAppearance: Hashable {
    case light
    case dark

    /// The app's current look. Vibrant and high-contrast variants count as
    /// their light or dark base; an appearance that matches neither is light.
    @MainActor
    static var current: SystemAppearance {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}
