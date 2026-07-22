//
//  MenuBarTintKind.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A type that specifies how the menu bar is tinted.
nonisolated enum MenuBarTintKind: Int, CaseIterable, Identifiable {
    /// The menu bar is not tinted.
    case noTint = 0
    /// The menu bar is tinted with a solid color.
    case solid = 1
    /// The menu bar is tinted with a gradient.
    case gradient = 2
    /// The menu bar is tinted with a glass effect.
    case glass = 3
    /// The menu bar is tinted with an adaptive color from the desktop wallpaper.
    case adaptive = 4

    var id: Int {
        rawValue
    }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .noTint: "None"
        case .solid: "Solid"
        case .gradient: "Gradient"
        case .glass: "Glass"
        case .adaptive: "Adaptive"
        }
    }
}

nonisolated extension MenuBarTintKind: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int.self)
        guard let value = MenuBarTintKind(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid MenuBarTintKind: \(rawValue)"
            )
        }
        self = value
    }
}
