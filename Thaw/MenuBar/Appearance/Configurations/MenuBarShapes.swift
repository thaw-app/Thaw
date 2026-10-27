//
//  MenuBarShapes.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// How one end of a menu bar shape is finished off.
nonisolated enum MenuBarEndCap: Int, CaseIterable, Codable, Hashable {
    /// A flat end, flush with the edge of the bar.
    case square = 0
    /// An end rounded off into a half-circle.
    case round = 1
}

/// The outline the appearance overlay cuts the menu bar down to.
nonisolated enum MenuBarShapeKind: Int, CaseIterable, Identifiable {
    /// No outline; the appearance covers the bar edge to edge.
    case noShape = 0
    /// One outline spanning the whole width of the bar.
    case full = 1
    /// Two outlines, one around the leading items and one around
    /// the trailing items.
    case split = 2
    /// A shape that behaves like full on non-notched displays,
    /// and splits at the notch on notched displays.
    case notch = 3

    var id: Int {
        rawValue
    }

    /// Whether the shape is drawn around the items, so drawing it needs to know where they are.
    /// Every other shape spans the bar, or the bar up to the notch, wherever the items sit.
    var followsItems: Bool {
        self == .split
    }

    /// The name shown for this kind in the settings UI.
    var localized: LocalizedStringKey {
        switch self {
        case .noShape: "None"
        case .full: "Full"
        case .split: "Split"
        case .notch: "Notch"
        }
    }

    /// What the kind does, for the shape picker's tooltip.
    var caption: LocalizedStringKey {
        switch self {
        case .noShape: "The look covers the whole menu bar."
        case .full: "One shape across the menu bar."
        case .split: "One shape around the app menus, one around the icons."
        case .notch: "Full on a display without a notch, split at the notch on one with a notch."
        }
    }
}

nonisolated extension MenuBarShapeKind: Codable {
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

/// The end caps MenuBarShapeKind.full draws the bar with.
nonisolated struct MenuBarFullShapeInfo: Hashable {
    /// How the left-hand end of the shape is finished.
    var leadingEndCap: MenuBarEndCap
    /// How the right-hand end of the shape is finished.
    var trailingEndCap: MenuBarEndCap
    /// How far a round end curves, from 0 (square corners) to 1 (a half-circle the bar's height).
    var roundness: Double = 1
}

nonisolated extension MenuBarFullShapeInfo: Codable {
    private enum CodingKeys: CodingKey {
        case leadingEndCap
        case trailingEndCap
        case roundness
    }

    init(from decoder: any Decoder) throws {
        let stored = try decoder.container(keyedBy: CodingKeys.self)
        leadingEndCap = try stored.decode(MenuBarEndCap.self, forKey: .leadingEndCap)
        trailingEndCap = try stored.decode(MenuBarEndCap.self, forKey: .trailingEndCap)
        // Looks saved before the slider existed had fully round ends.
        // A damaged record is read inside 0 to 1, and as round when it isn't a number.
        let decoded = try stored.decodeIfPresent(Double.self, forKey: .roundness) ?? 1
        roundness = decoded.isFinite ? min(max(decoded, 0), 1) : 1
    }
}

nonisolated extension MenuBarFullShapeInfo {
    /// Whether either end of the shape is rounded.
    var hasRoundedShape: Bool {
        leadingEndCap.isRounded || trailingEndCap.isRounded
    }
}

nonisolated extension MenuBarFullShapeInfo {
    static let defaultValue = MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .round)
}

/// A shape drawn as two full shapes, one around the leading items and one
/// around the trailing items.
nonisolated protocol MenuBarTwoPartShapeInfo {
    var leading: MenuBarFullShapeInfo { get }
    var trailing: MenuBarFullShapeInfo { get }
}

nonisolated extension MenuBarTwoPartShapeInfo {
    /// Whether either part rounds off an end.
    var hasRoundedShape: Bool {
        [leading, trailing].contains(where: \.hasRoundedShape)
    }

    /// The caps on the outermost ends of the two parts, what one full-width
    /// shape wears in their place: when a split collapses into one, or on a
    /// display without a notch.
    var outerEndCaps: MenuBarFullShapeInfo {
        MenuBarFullShapeInfo(
            leadingEndCap: leading.leadingEndCap,
            trailingEndCap: trailing.trailingEndCap,
            roundness: leading.roundness
        )
    }
}

/// The two sub-shapes MenuBarShapeKind.split draws the bar with.
nonisolated struct MenuBarSplitShapeInfo: Codable, Hashable, MenuBarTwoPartShapeInfo {
    /// The sub-shape drawn around the leading items.
    var leading: MenuBarFullShapeInfo
    /// The sub-shape drawn around the trailing items.
    var trailing: MenuBarFullShapeInfo
}

nonisolated extension MenuBarSplitShapeInfo {
    static let defaultValue = MenuBarSplitShapeInfo(leading: .defaultValue, trailing: .defaultValue)
}

/// Information for the MenuBarShapeKind.notch menu bar shape kind.
///
/// Without a notch it falls back to full width, using the leading cap on the
/// left and the trailing cap on the right.
nonisolated struct MenuBarNotchShapeInfo: Codable, Hashable, MenuBarTwoPartShapeInfo {
    /// The leading shape info.
    var leading: MenuBarFullShapeInfo
    /// The trailing shape info.
    var trailing: MenuBarFullShapeInfo
}

nonisolated extension MenuBarNotchShapeInfo {
    static let defaultValue = MenuBarNotchShapeInfo(leading: .defaultValue, trailing: .defaultValue)
}

/// A type that specifies how the background surrounding the shape is rendered.
nonisolated enum MenuBarBackgroundKind: Int, CaseIterable, Codable, Hashable {
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

nonisolated extension MenuBarBackgroundKind {
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

nonisolated extension MenuBarBackgroundKind {
    /// App-level default for background rendering in appearance configs.
    static let appDefault = MenuBarBackgroundKind.none
}

/// A type that specifies which glass style to use for glass backgrounds and tints.
nonisolated enum MenuBarGlassStyle: Int, CaseIterable, Codable, Hashable {
    /// Standard glass effect.
    case regular = 0
    /// Clear glass effect.
    case clear = 1
    /// Clear Liquid Glass without a color wash.
    case liquid = 2
    /// Clear Liquid Glass with a dark-to-clear vertical fade.
    case dynamic = 3
    /// Experimental: glass that inverts what's behind it, from the private variant 6.
    /// Shown as Invert. The case keeps solid, the name it first had.
    case solid = 4
    /// Experimental: clear glass with a bright rim, from the private variant 11.
    case edge = 5
    /// Experimental: soft, thin clear glass, from the private variant 15.
    case sheer = 6
    /// Experimental: a haze in light mode and smoky glass in dark mode, from the private variant 18.
    case dim = 7

    @MainActor
    var nsGlassStyle: NSGlassEffectView.Style {
        switch self {
        case .regular, .solid, .dim: .regular
        case .clear, .liquid, .dynamic, .edge, .sheer: .clear
        }
    }

    /// The private _variant the finish needs, or nil for the public styles.
    var privateVariant: Int? {
        switch self {
        case .regular, .clear, .liquid, .dynamic: nil
        case .solid: 6
        case .edge: 11
        case .sheer: 15
        case .dim: 18
        }
    }

    /// The finishes built on private settings, marked experimental in Settings.
    var isExperimental: Bool {
        privateVariant != nil
    }

    /// Whether the finish takes the icons' light or dark. Invert doesn't: dark,
    /// it turns bright and would hide light icons.
    var followsIconShade: Bool {
        isExperimental && self != .solid
    }

    /// How dark the finish makes what's behind it, for reading the icons' contrast.
    var darkening: Double {
        self == .dim ? 0.5 : 0
    }

    var usesTint: Bool {
        self == .liquid || self == .dynamic
    }

    var usesShapeAwareSurface: Bool {
        self == .liquid || self == .dynamic
    }

    var usesDarkFade: Bool {
        self == .dynamic
    }

    var effectOpacity: Double {
        switch self {
        case .regular, .clear, .solid, .edge, .sheer, .dim: 1
        case .liquid, .dynamic: 0.45
        }
    }

    var localized: LocalizedStringKey {
        switch self {
        case .regular: "Regular"
        case .clear: "Clear"
        case .liquid: "Liquid Glass"
        case .dynamic: "Dynamic Glass"
        case .solid: "Invert (Experimental)"
        case .edge: "Edge (Experimental)"
        case .sheer: "Sheer (Experimental)"
        case .dim: "Dim (Experimental)"
        }
    }
}

// MARK: - MenuBarEndCap

private nonisolated extension MenuBarEndCap {
    /// Whether this cap rounds off the end it terminates.
    var isRounded: Bool {
        self == .round
    }
}

// MARK: - MenuBarBorderStyle

/// How the shape's border line is drawn.
nonisolated enum MenuBarBorderStyle: Int, CaseIterable, Codable, Hashable {
    case solid = 0
    case dashed = 1
    case dotted = 2

    var localized: LocalizedStringKey {
        switch self {
        case .solid: "Solid"
        case .dashed: "Dashed"
        case .dotted: "Dotted"
        }
    }

    /// The dash pattern for a border width points wide, or nil for a
    /// solid line. Butt caps, so a dot is a square as wide as the line.
    func dashPattern(width: Double) -> [CGFloat]? {
        switch self {
        case .solid: nil
        case .dashed: [CGFloat(width * 4), CGFloat(width * 3)]
        case .dotted: [CGFloat(width), CGFloat(width * 1.5)]
        }
    }
}
