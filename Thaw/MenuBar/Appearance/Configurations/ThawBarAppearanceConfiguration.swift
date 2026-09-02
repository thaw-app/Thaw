//
//  ThawBarAppearanceConfiguration.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - ThawBarBackgroundKind

/// How the Thaw Bar fills its panel background.
///
/// Independent of ``MenuBarBackgroundKind``: the menu bar paints into an
/// overlay behind system items, while the Thaw Bar owns a freestanding panel
/// and therefore needs its own fill model (including an adaptive sample of
/// the live menu bar / wallpaper).
nonisolated enum ThawBarBackgroundKind: Int, CaseIterable, Hashable, Identifiable {
    /// System clear liquid glass — the same family of material as the menu bar,
    /// so the panel tracks wallpaper tone instead of painting a flat sample.
    case adaptive = 0
    /// A solid color fill.
    case solid = 1
    /// A gradient fill.
    case gradient = 2
    /// System liquid glass with a configurable Regular / Clear style.
    case glass = 3
    /// No fill; only tint, border, and shadow (if enabled) remain visible.
    case none = 4
    /// Flat average of the menu bar / wallpaper strip. Looks darker than the
    /// real menu bar because it has no translucency; kept for users who want
    /// an opaque matched swatch.
    case sampled = 5

    var id: Int { rawValue }

    var localized: LocalizedStringKey {
        switch self {
        case .adaptive: "Match Menu Bar"
        case .solid: "Solid"
        case .gradient: "Gradient"
        case .glass: "Glass"
        case .none: "None"
        case .sampled: "Sampled Color"
        }
    }

    /// Whether this kind always draws through SwiftUI liquid glass.
    /// Match Menu Bar opts in separately via ``ThawBarAppearancePartialConfiguration/adaptiveGlassAmount``.
    var usesLiquidGlass: Bool {
        switch self {
        case .glass: true
        case .adaptive, .solid, .gradient, .none, .sampled: false
        }
    }
}

nonisolated extension ThawBarBackgroundKind: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int.self)
        guard let value = ThawBarBackgroundKind(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ThawBarBackgroundKind: \(rawValue)"
            )
        }
        self = value
    }
}

// MARK: - ThawBarCornerStyle

/// Corner treatment for the Thaw Bar panel, independent of the menu bar shape.
nonisolated enum ThawBarCornerStyle: Int, CaseIterable, Hashable, Identifiable {
    /// Capsule ends (fully rounded).
    case rounded = 0
    /// Squared ends with a small continuous radius.
    case square = 1

    var id: Int { rawValue }

    var localized: LocalizedStringKey {
        switch self {
        case .rounded: "Rounded"
        case .square: "Square"
        }
    }

    /// Whether this style uses the pill (fully rounded) clip path.
    var isFullyRounded: Bool {
        switch self {
        case .rounded: true
        case .square: false
        }
    }
}

nonisolated extension ThawBarCornerStyle: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int.self)
        guard let value = ThawBarCornerStyle(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ThawBarCornerStyle: \(rawValue)"
            )
        }
        self = value
    }
}

// MARK: - ThawBarAppearancePartialConfiguration

/// Appearance knobs that apply to the Thaw Bar for one appearance mode
/// (static, light, or dark).
nonisolated struct ThawBarAppearancePartialConfiguration: Hashable {
    var backgroundKind: ThawBarBackgroundKind
    var backgroundColor: CGColor
    var backgroundGradient: IceGradient
    /// Opacity applied to solid, gradient, and sampled fills (`0...1`).
    var backgroundOpacity: Double
    var backgroundGlassStyle: MenuBarGlassStyle

    /// Brightness offset for Match Menu Bar fills (`-1...1`, `0` = as sampled).
    /// Positive values mix toward white; negative values mix toward black.
    var adaptiveBrightness: Double
    /// Liquid-glass blend for Match Menu Bar (`0...1`, `0` = opaque sample only).
    var adaptiveGlassAmount: Double

    var tintKind: MenuBarTintKind
    var tintColor: CGColor
    var tintGradient: IceGradient
    /// Opacity applied to solid and gradient tints (`0...1`).
    var tintOpacity: Double

    var cornerStyle: ThawBarCornerStyle

    var hasBorder: Bool
    var borderColor: CGColor
    var borderWidth: Double
    /// When the corners are square, skip the top edge of the border so the
    /// stroke is not clipped by the display's rounded corners (#325).
    var omitTopBorderWhenSquare: Bool

    /// Whether the panel window draws its native drop shadow.
    var hasShadow: Bool
}

// MARK: Default

nonisolated extension ThawBarAppearancePartialConfiguration {
    /// Defaults chosen so a fresh install matches the system menu bar tone
    /// via clear liquid glass (same material family as the menu bar).
    static let defaultConfiguration = ThawBarAppearancePartialConfiguration(
        backgroundKind: .adaptive,
        backgroundColor: .black,
        backgroundGradient: .defaultMenuBarTint,
        backgroundOpacity: 1,
        backgroundGlassStyle: .clear,
        adaptiveBrightness: 0,
        adaptiveGlassAmount: 0,
        tintKind: .noTint,
        tintColor: .black,
        tintGradient: .defaultMenuBarTint,
        tintOpacity: 0.2,
        cornerStyle: .rounded,
        hasBorder: false,
        borderColor: .black,
        borderWidth: 1,
        omitTopBorderWhenSquare: true,
        hasShadow: true
    )

    /// Builds a Thaw Bar partial from a pre-split menu bar partial that still
    /// carried `borderOnThawBar` / shared tint. Match-menu-bar glass + migrated
    /// border; tint defaults to none so upgrading clears the historical black
    /// overlay that made the bar look darker than the menu bar.
    static func migrating(from menuBarPartial: MenuBarAppearancePartialConfiguration) -> ThawBarAppearancePartialConfiguration {
        ThawBarAppearancePartialConfiguration(
            backgroundKind: .adaptive,
            backgroundColor: menuBarPartial.backgroundColor,
            backgroundGradient: menuBarPartial.backgroundGradient,
            backgroundOpacity: 1,
            backgroundGlassStyle: .clear,
            adaptiveBrightness: 0,
            adaptiveGlassAmount: 0,
            tintKind: .noTint,
            tintColor: menuBarPartial.tintColor,
            tintGradient: menuBarPartial.tintGradient,
            tintOpacity: menuBarPartial.tintOpacity,
            cornerStyle: .rounded,
            hasBorder: menuBarPartial.borderOnThawBar,
            borderColor: menuBarPartial.borderColor,
            borderWidth: menuBarPartial.borderWidth,
            omitTopBorderWhenSquare: true,
            hasShadow: true
        )
    }
}

// MARK: Codable

nonisolated extension ThawBarAppearancePartialConfiguration: Codable {
    private enum CodingKeys: CodingKey {
        case backgroundKind
        case backgroundColor
        case backgroundGradient
        case backgroundOpacity
        case backgroundGlassStyle
        case adaptiveBrightness
        case adaptiveGlassAmount
        case tintKind
        case tintColor
        case tintGradient
        case tintOpacity
        case cornerStyle
        case hasBorder
        case borderColor
        case borderWidth
        case omitTopBorderWhenSquare
        case hasShadow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaultConfiguration
        try self.init(
            backgroundKind: container.decodeIfPresent(ThawBarBackgroundKind.self, forKey: .backgroundKind) ?? defaults.backgroundKind,
            backgroundColor: container.decodeIfPresent(IceColor.self, forKey: .backgroundColor)?.cgColor ?? defaults.backgroundColor,
            backgroundGradient: container.decodeIfPresent(IceGradient.self, forKey: .backgroundGradient) ?? defaults.backgroundGradient,
            backgroundOpacity: container.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? defaults.backgroundOpacity,
            backgroundGlassStyle: container.decodeIfPresent(MenuBarGlassStyle.self, forKey: .backgroundGlassStyle) ?? defaults.backgroundGlassStyle,
            adaptiveBrightness: container.decodeIfPresent(Double.self, forKey: .adaptiveBrightness) ?? defaults.adaptiveBrightness,
            adaptiveGlassAmount: container.decodeIfPresent(Double.self, forKey: .adaptiveGlassAmount) ?? defaults.adaptiveGlassAmount,
            tintKind: container.decodeIfPresent(MenuBarTintKind.self, forKey: .tintKind) ?? defaults.tintKind,
            tintColor: container.decodeIfPresent(IceColor.self, forKey: .tintColor)?.cgColor ?? defaults.tintColor,
            tintGradient: container.decodeIfPresent(IceGradient.self, forKey: .tintGradient) ?? defaults.tintGradient,
            tintOpacity: container.decodeIfPresent(Double.self, forKey: .tintOpacity) ?? defaults.tintOpacity,
            cornerStyle: container.decodeIfPresent(ThawBarCornerStyle.self, forKey: .cornerStyle) ?? defaults.cornerStyle,
            hasBorder: container.decodeIfPresent(Bool.self, forKey: .hasBorder) ?? defaults.hasBorder,
            borderColor: container.decodeIfPresent(IceColor.self, forKey: .borderColor)?.cgColor ?? defaults.borderColor,
            borderWidth: container.decodeIfPresent(Double.self, forKey: .borderWidth) ?? defaults.borderWidth,
            omitTopBorderWhenSquare: container.decodeIfPresent(Bool.self, forKey: .omitTopBorderWhenSquare) ?? defaults.omitTopBorderWhenSquare,
            hasShadow: container.decodeIfPresent(Bool.self, forKey: .hasShadow) ?? defaults.hasShadow
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(backgroundKind, forKey: .backgroundKind)
        try container.encode(IceColor(cgColor: backgroundColor), forKey: .backgroundColor)
        try container.encode(backgroundGradient, forKey: .backgroundGradient)
        try container.encode(backgroundOpacity, forKey: .backgroundOpacity)
        try container.encode(backgroundGlassStyle, forKey: .backgroundGlassStyle)
        try container.encode(adaptiveBrightness, forKey: .adaptiveBrightness)
        try container.encode(adaptiveGlassAmount, forKey: .adaptiveGlassAmount)
        try container.encode(tintKind, forKey: .tintKind)
        try container.encode(IceColor(cgColor: tintColor), forKey: .tintColor)
        try container.encode(tintGradient, forKey: .tintGradient)
        try container.encode(tintOpacity, forKey: .tintOpacity)
        try container.encode(cornerStyle, forKey: .cornerStyle)
        try container.encode(hasBorder, forKey: .hasBorder)
        try container.encode(IceColor(cgColor: borderColor), forKey: .borderColor)
        try container.encode(borderWidth, forKey: .borderWidth)
        try container.encode(omitTopBorderWhenSquare, forKey: .omitTopBorderWhenSquare)
        try container.encode(hasShadow, forKey: .hasShadow)
    }
}

// MARK: - Effective fill helpers

nonisolated extension ThawBarAppearancePartialConfiguration {
    /// Whether the top edge of the border should be omitted for the current
    /// corner style and omit-top preference (#325).
    var shouldOmitTopBorder: Bool {
        hasBorder && !cornerStyle.isFullyRounded && omitTopBorderWhenSquare
    }

    /// Whether liquid glass should be applied for the current fill settings.
    var appliesLiquidGlass: Bool {
        switch backgroundKind {
        case .glass:
            true
        case .adaptive:
            adaptiveGlassAmount > 0
        case .solid, .gradient, .none, .sampled:
            false
        }
    }

    /// Corner radius for the clip path given the bar's content height.
    func cornerRadius(contentHeight: CGFloat) -> CGFloat {
        switch cornerStyle {
        case .rounded:
            contentHeight / 2
        case .square:
            contentHeight / 4
        }
    }

    /// Match Menu Bar fill opacity: higher glass amount lets more liquid glass show.
    var adaptiveFillOpacity: Double {
        max(0.12, 1 - adaptiveGlassAmount * 0.88)
    }

    /// Sampled color with ``adaptiveBrightness`` applied (Match Menu Bar).
    func brightnessAdjustedSample(from color: CGColor) -> CGColor {
        Self.adjustingBrightness(of: color, by: adaptiveBrightness) ?? color
    }

    /// Resolved fill color used for icon contrast when a concrete color is
    /// available (sampled strip, solid, or a representative gradient stop).
    ///
    /// Translucent fills are composited over ``sampled`` with the same opacity
    /// ``ThawBarChrome`` paints, so glyph contrast tracks the visible panel
    /// rather than the full-opacity source color.
    func resolvedFillColor(sampled: CGColor?) -> CGColor? {
        switch backgroundKind {
        case .adaptive:
            guard let sampled else { return nil }
            let fill = brightnessAdjustedSample(from: sampled)
            return Self.compositing(fill, over: sampled, opacity: adaptiveFillOpacity)
        case .glass, .none, .sampled:
            return sampled
        case .solid:
            return Self.compositing(backgroundColor, over: sampled, opacity: backgroundOpacity)
        case .gradient:
            // Avoid ``IceGradient/averageColor`` here: that API is `@MainActor`
            // because it renders through AppKit. A middle-stop blend is enough
            // for icon contrast decisions from nonisolated configuration code.
            let fill = representativeGradientColor ?? backgroundColor
            return Self.compositing(fill, over: sampled, opacity: backgroundOpacity)
        }
    }

    /// A representative color from ``backgroundGradient`` for contrast,
    /// interpolated at location `0.5` when neighboring stops exist.
    private var representativeGradientColor: CGColor? {
        guard !backgroundGradient.stops.isEmpty else { return nil }
        let sorted = backgroundGradient.stops.sorted { $0.location < $1.location }
        if sorted.count == 1 {
            return sorted[0].color
        }
        if let exact = sorted.first(where: { abs($0.location - 0.5) < 0.000_1 }) {
            return exact.color
        }
        guard
            let lower = sorted.last(where: { $0.location <= 0.5 }),
            let upper = sorted.first(where: { $0.location >= 0.5 })
        else {
            return sorted[sorted.count / 2].color
        }
        if lower.location == upper.location {
            return lower.color
        }
        let t = (0.5 - lower.location) / (upper.location - lower.location)
        return Self.blend(lower.color, upper.color, t: t) ?? lower.color
    }

    /// Linear blend of two device-RGB colors.
    private static func blend(_ a: CGColor, _ b: CGColor, t: Double) -> CGColor? {
        guard
            let rgbA = a.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
            let rgbB = b.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
            let ca = rgbA.components, ca.count >= 3,
            let cb = rgbB.components, cb.count >= 3
        else {
            return nil
        }
        let clamped = min(max(t, 0), 1)
        let aa = ca.count > 3 ? ca[3] : 1
        let ab = cb.count > 3 ? cb[3] : 1
        let r = ca[0] + (cb[0] - ca[0]) * clamped
        let g = ca[1] + (cb[1] - ca[1]) * clamped
        let bl = ca[2] + (cb[2] - ca[2]) * clamped
        let alpha = aa + (ab - aa) * clamped
        return CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, bl, alpha])
    }

    /// Paints `fill` at `opacity` over an opaque `underlay`, matching SwiftUI
    /// `.opacity` compositing for contrast decisions.
    private static func compositing(_ fill: CGColor, over underlay: CGColor?, opacity: Double) -> CGColor {
        let clamped = min(max(opacity, 0), 1)
        if clamped >= 1 { return fill }
        guard let underlay else { return fill }
        return blend(underlay, fill, t: clamped) ?? fill
    }

    /// Whether icon glyphs should render dark on top of the resolved fill.
    ///
    /// Takes precomputed notch / brightness inputs so this stays usable from
    /// `nonisolated` configuration code without touching `NSScreen`.
    func prefersDarkForeground(
        sampledColor: CGColor?,
        sampledBrightness: CGFloat?,
        screenHasNotch: Bool
    ) -> Bool {
        let threshold = screenHasNotch
            ? Constants.notchedDisplayBrightnessThreshold
            : Constants.menuBarBrightnessThreshold
        if let fill = resolvedFillColor(sampled: sampledColor) {
            let brightness = Self.relativeLuminance(of: fill) ?? sampledBrightness ?? 0
            return brightness > threshold
        }
        return (sampledBrightness ?? 0) > threshold
    }

    /// Mixes `color` toward white (`amount > 0`) or black (`amount < 0`).
    /// `amount` is clamped to `-1...1`; `0` returns the original color.
    static func adjustingBrightness(of color: CGColor, by amount: Double) -> CGColor? {
        let clamped = min(max(amount, -1), 1)
        guard clamped != 0 else { return color }
        guard
            let rgb = color.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
            let components = rgb.components,
            components.count >= 3
        else {
            return nil
        }
        let alpha = components.count > 3 ? components[3] : 1
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        if clamped > 0 {
            let t = CGFloat(clamped)
            r = components[0] + (1 - components[0]) * t
            g = components[1] + (1 - components[1]) * t
            b = components[2] + (1 - components[2]) * t
        } else {
            let t = CGFloat(1 + clamped)
            r = components[0] * t
            g = components[1] * t
            b = components[2] * t
        }
        return CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, alpha])
    }

    /// W3C relative luminance for an sRGB-ish color, computed without the
    /// MainActor-bound ``CGColor/brightness`` helper.
    private static func relativeLuminance(of color: CGColor) -> CGFloat? {
        guard
            let rgb = color.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
            let components = rgb.components,
            components.count >= 3
        else {
            return nil
        }
        return ((components[0] * 299) + (components[1] * 587) + (components[2] * 114)) / 1000
    }
}
