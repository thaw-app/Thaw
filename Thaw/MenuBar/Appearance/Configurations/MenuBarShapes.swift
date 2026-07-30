//
//  MenuBarShapes.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// An end cap in a menu bar shape.
enum MenuBarEndCap: Int, CaseIterable, Codable, Hashable {
    /// An end cap with a square shape.
    case square = 0
    /// An end cap with a rounded shape.
    case round = 1
}

/// A type that specifies a custom shape kind for the menu bar.
enum MenuBarShapeKind: Int, CaseIterable, Identifiable {
    /// The menu bar does not use a custom shape.
    case noShape = 0
    /// A custom shape that takes up the full menu bar.
    case full = 1
    /// A custom shape that splits the menu bar between its leading
    /// and trailing sides.
    case split = 2
    /// A shape that behaves like full on non-notched displays,
    /// and splits at the notch on notched displays.
    case notch = 3

    var id: Int {
        rawValue
    }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .noShape: "None"
        case .full: "Full"
        case .split: "Split"
        case .notch: "Notch"
        }
    }
}

extension MenuBarShapeKind: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int.self)
        if rawValue == 3 {
            self = .notch
        } else {
            guard let value = MenuBarShapeKind(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid MenuBarShapeKind: \(rawValue)"
                )
            }
            self = value
        }
    }
}

/// Information for the ``MenuBarShapeKind/full`` menu bar shape kind.
struct MenuBarFullShapeInfo: Codable, Hashable {
    /// The leading end cap of the shape.
    var leadingEndCap: MenuBarEndCap
    /// The trailing end cap of the shape.
    var trailingEndCap: MenuBarEndCap
}

extension MenuBarFullShapeInfo {
    var hasRoundedShape: Bool {
        leadingEndCap == .round || trailingEndCap == .round
    }
}

extension MenuBarFullShapeInfo {
    static let defaultValue = MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .round)
}

/// Information for the ``MenuBarShapeKind/split`` menu bar shape kind.
struct MenuBarSplitShapeInfo: Codable, Hashable {
    /// The leading information of the shape.
    var leading: MenuBarFullShapeInfo
    /// The trailing information of the shape.
    var trailing: MenuBarFullShapeInfo
}

extension MenuBarSplitShapeInfo {
    var hasRoundedShape: Bool {
        leading.hasRoundedShape || trailing.hasRoundedShape
    }
}

extension MenuBarSplitShapeInfo {
    static let defaultValue = MenuBarSplitShapeInfo(leading: .defaultValue, trailing: .defaultValue)
}

/// Information for the ``MenuBarShapeKind/notch`` menu bar shape kind.
///
/// Uses ``MenuBarSplitShapeInfo`` internally — each side has its own
/// end-cap configuration. On non-notched displays the shape falls back
/// to full-width, using the leading end-cap for the left corner and the
/// trailing end-cap for the right corner.
struct MenuBarNotchShapeInfo: Codable, Hashable {
    /// The leading shape info.
    var leading: MenuBarFullShapeInfo
    /// The trailing shape info.
    var trailing: MenuBarFullShapeInfo
}

extension MenuBarNotchShapeInfo {
    var hasRoundedShape: Bool {
        leading.hasRoundedShape || trailing.hasRoundedShape
    }
}

extension MenuBarNotchShapeInfo {
    static let defaultValue = MenuBarNotchShapeInfo(leading: .defaultValue, trailing: .defaultValue)
}

/// A type that specifies how the background surrounding the shape is rendered.
enum MenuBarBackgroundKind: Int, CaseIterable, Codable, Hashable {
    /// No background.
    case none = 0
    /// A solid color background.
    case solid = 1
    /// A gradient background.
    case gradient = 2
    /// A glass-material background.
    case glass = 3
    /// An adaptive background that uses the average color of the desktop wallpaper.
    case adaptive = 4
}

extension MenuBarBackgroundKind {
    var localized: LocalizedStringKey {
        switch self {
        case .none: "None"
        case .solid: "Solid"
        case .gradient: "Gradient"
        case .glass: "Glass"
        case .adaptive: "Adaptive"
        }
    }
}

extension MenuBarBackgroundKind {
    /// App-level default for background rendering in appearance configs.
    /// Named `default` for call-site readability (`.default`), escaped because `default` is a Swift keyword.
    static let `default` = MenuBarBackgroundKind.none
}

/// A type that specifies which glass style to use for glass backgrounds and tints.
enum MenuBarGlassStyle: Int, CaseIterable, Codable, Hashable {
    /// Standard glass effect.
    case regular = 0
    /// Clear glass effect.
    case clear = 1

    var nsGlassStyle: NSGlassEffectView.Style {
        switch self {
        case .regular: .regular
        case .clear: .clear
        }
    }

    var localized: LocalizedStringKey {
        switch self {
        case .regular: "Regular"
        case .clear: "Clear"
        }
    }
}
