//
//  MenuBarAppearanceConfigurationV2.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Shape and margins apply to every appearance; partial configurations supply static or dynamic light/dark colors, tints, and backgrounds.
/// Stored property names are persistence keys.
nonisolated struct MenuBarAppearanceConfigurationV2: Hashable {
    var lightModeConfiguration: MenuBarAppearancePartialConfiguration
    var darkModeConfiguration: MenuBarAppearancePartialConfiguration
    var staticConfiguration: MenuBarAppearancePartialConfiguration
    var shapeKind: MenuBarShapeKind
    var fullShapeInfo: MenuBarFullShapeInfo
    var splitShapeInfo: MenuBarSplitShapeInfo
    var notchShapeInfo: MenuBarNotchShapeInfo
    var isInset: Bool
    var leftMargin: Double
    var rightMargin: Double
    var notchMargin: Double
    var isDynamic: Bool
    /// The Thaw Bar's own appearance, when it does not match the menu bar's.
    var thawBarAppearance: ThawBarAppearance

    /// Only the selected shape's info determines rounding; other shape settings are ignored.
    var hasRoundedShape: Bool {
        switch shapeKind {
        case .noShape: false
        case .full: fullShapeInfo.hasRoundedShape
        case .split: splitShapeInfo.hasRoundedShape
        case .notch: notchShapeInfo.hasRoundedShape
        }
    }

    /// Dynamic colors track system appearance; otherwise use staticConfiguration.
    @MainActor
    var current: MenuBarAppearancePartialConfiguration {
        guard isDynamic else {
            return staticConfiguration
        }
        return switch SystemAppearance.current {
        case .light: lightModeConfiguration
        case .dark: darkModeConfiguration
        }
    }

    /// Resolves the entire floating bar appearance from its selected owner.
    @MainActor
    var resolvedThawBarAppearance: ResolvedThawBarAppearance {
        if thawBarAppearance.overridesMenuBar {
            return ResolvedThawBarAppearance(
                hasRoundedShape: thawBarAppearance.hasRoundedShape,
                fillConfiguration: thawBarAppearance.fillConfiguration
            )
        }
        // The menu bar strokes its border along its shape, so with no shape
        // it draws none; the Thaw Bar must not either.
        var fill = current
        if shapeKind == .noShape {
            fill.hasBorder = false
        }
        return ResolvedThawBarAppearance(hasRoundedShape: hasRoundedShape, fillConfiguration: fill)
    }
}

// MARK: Default Configuration

nonisolated extension MenuBarAppearanceConfigurationV2 {
    static let defaultConfiguration = MenuBarAppearanceConfigurationV2(
        lightModeConfiguration: .defaultConfiguration,
        darkModeConfiguration: .defaultConfiguration,
        staticConfiguration: .defaultConfiguration,
        shapeKind: .noShape,
        fullShapeInfo: .defaultValue,
        splitShapeInfo: .defaultValue,
        notchShapeInfo: .defaultValue,
        isInset: true,
        leftMargin: 0,
        rightMargin: 0,
        notchMargin: 0,
        isDynamic: false,
        thawBarAppearance: .defaultConfiguration
    )
}

nonisolated extension MenuBarAppearanceConfigurationV2: Codable {
    /// Case names are on-disk keys; renaming them strands stored values.
    private enum CodingKeys: CodingKey {
        case lightModeConfiguration
        case darkModeConfiguration
        case staticConfiguration
        case shapeKind
        case fullShapeInfo
        case splitShapeInfo
        case notchShapeInfo
        case isInset
        case leftMargin
        case rightMargin
        case notchMargin
        case isDynamic
        case thawBarAppearance
    }

    init(from decoder: any Decoder) throws {
        let stored = try decoder.container(keyedBy: CodingKeys.self)

        // Every key is optional on read: settings written before a property
        // existed simply take that property's default.
        let fallback = Self.defaultConfiguration

        try self.init(
            lightModeConfiguration: stored.value(forKey: .lightModeConfiguration, or: fallback.lightModeConfiguration),
            darkModeConfiguration: stored.value(forKey: .darkModeConfiguration, or: fallback.darkModeConfiguration),
            staticConfiguration: stored.value(forKey: .staticConfiguration, or: fallback.staticConfiguration),
            shapeKind: stored.value(forKey: .shapeKind, or: fallback.shapeKind),
            fullShapeInfo: stored.value(forKey: .fullShapeInfo, or: fallback.fullShapeInfo),
            splitShapeInfo: stored.value(forKey: .splitShapeInfo, or: fallback.splitShapeInfo),
            notchShapeInfo: stored.value(forKey: .notchShapeInfo, or: fallback.notchShapeInfo),
            isInset: stored.value(forKey: .isInset, or: fallback.isInset),
            leftMargin: stored.value(forKey: .leftMargin, or: fallback.leftMargin),
            rightMargin: stored.value(forKey: .rightMargin, or: fallback.rightMargin),
            notchMargin: stored.value(forKey: .notchMargin, or: fallback.notchMargin),
            isDynamic: stored.value(forKey: .isDynamic, or: fallback.isDynamic),
            thawBarAppearance: stored.decodeIfPresent(ThawBarAppearance.self, forKey: .thawBarAppearance) ?? fallback.thawBarAppearance
        )
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(lightModeConfiguration, forKey: .lightModeConfiguration)
        try values.encode(darkModeConfiguration, forKey: .darkModeConfiguration)
        try values.encode(staticConfiguration, forKey: .staticConfiguration)
        try values.encode(shapeKind, forKey: .shapeKind)
        try values.encode(fullShapeInfo, forKey: .fullShapeInfo)
        try values.encode(splitShapeInfo, forKey: .splitShapeInfo)
        try values.encode(notchShapeInfo, forKey: .notchShapeInfo)
        try values.encode(isInset, forKey: .isInset)
        try values.encode(leftMargin, forKey: .leftMargin)
        try values.encode(rightMargin, forKey: .rightMargin)
        try values.encode(notchMargin, forKey: .notchMargin)
        try values.encode(isDynamic, forKey: .isDynamic)
        try values.encode(thawBarAppearance, forKey: .thawBarAppearance)
    }
}

// MARK: - MenuBarAppearancePartialConfiguration

/// Per-mode tint, background, border, and shadow settings.
/// Stored property names are persistence keys.
nonisolated struct MenuBarAppearancePartialConfiguration: Hashable {
    var hasShadow: Bool
    var hasBorder: Bool
    var borderColor: CGColor
    var borderWidth: Double
    var tintKind: MenuBarTintKind
    var tintColor: CGColor
    var tintGradient: ThawGradient
    var tintOpacity: Double
    var backgroundKind: MenuBarBackgroundKind
    var backgroundColor: CGColor
    var backgroundGradient: ThawGradient
    var backgroundOpacity: Double
    var backgroundHasShadow: Bool
    var backgroundHasBorder: Bool
    var backgroundBorderColor: CGColor
    var backgroundBorderWidth: Double
    var backgroundGlassStyle: MenuBarGlassStyle
    var tintGlassStyle: MenuBarGlassStyle
    var backgroundGlassIsColored: Bool
    var tintGlassIsColored: Bool
    /// MenuBarAppearanceManager syncs the accent into backgroundColor so renderers and older builds see a plain color.
    var backgroundUsesAccentColor = false
    /// Whether tintColor follows the system accent color, as above.
    var tintUsesAccentColor = false
    /// Sync background glass with System Settings: Regular for Tinted, Clear for Clear.
    var backgroundGlassFollowsSystem = false
    /// Whether tintGlassStyle follows the system's Liquid Glass setting.
    var tintGlassFollowsSystem = false
    var borderStyle: MenuBarBorderStyle = .solid
}

// MARK: Default Partial Configuration

nonisolated extension MenuBarAppearancePartialConfiguration {
    static let defaultConfiguration = MenuBarAppearancePartialConfiguration(
        hasShadow: true,
        hasBorder: true,
        borderColor: .black,
        borderWidth: 1,
        tintKind: .solid,
        tintColor: .black,
        tintGradient: .defaultMenuBarTint,
        tintOpacity: 0.2,
        backgroundKind: .default,
        backgroundColor: .black,
        backgroundGradient: .defaultMenuBarTint,
        backgroundOpacity: 0.2,
        backgroundHasShadow: false,
        backgroundHasBorder: false,
        backgroundBorderColor: .black,
        backgroundBorderWidth: 1,
        backgroundGlassStyle: .regular,
        tintGlassStyle: .regular,
        backgroundGlassIsColored: false,
        tintGlassIsColored: false
    )
}

// MARK: MenuBarAppearancePartialConfiguration: Codable

nonisolated extension MenuBarAppearancePartialConfiguration: Codable {
    /// The names under which the values are stored. As above, the case names are
    /// the on-disk format and cannot be renamed.
    private enum CodingKeys: CodingKey {
        case hasShadow
        case hasBorder
        case borderColor
        case borderWidth
        case tintKind
        case tintColor
        case tintGradient
        case tintOpacity
        case backgroundKind
        case backgroundColor
        case backgroundGradient
        case backgroundOpacity
        case backgroundHasShadow
        case backgroundHasBorder
        case backgroundBorderColor
        case backgroundBorderWidth
        case backgroundGlassStyle
        case tintGlassStyle
        case backgroundGlassIsColored
        case tintGlassIsColored
        case backgroundUsesAccentColor
        case tintUsesAccentColor
        case backgroundGlassFollowsSystem
        case tintGlassFollowsSystem
        case borderStyle
    }

    init(from decoder: any Decoder) throws {
        let stored = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.defaultConfiguration

        try self.init(
            hasShadow: stored.value(forKey: .hasShadow, or: fallback.hasShadow),
            hasBorder: stored.value(forKey: .hasBorder, or: fallback.hasBorder),
            borderColor: stored.color(forKey: .borderColor, or: fallback.borderColor),
            borderWidth: stored.value(forKey: .borderWidth, or: fallback.borderWidth),
            tintKind: stored.value(forKey: .tintKind, or: fallback.tintKind),
            tintColor: stored.color(forKey: .tintColor, or: fallback.tintColor),
            tintGradient: stored.value(forKey: .tintGradient, or: fallback.tintGradient),
            tintOpacity: stored.value(forKey: .tintOpacity, or: fallback.tintOpacity),
            backgroundKind: stored.value(forKey: .backgroundKind, or: fallback.backgroundKind),
            backgroundColor: stored.color(forKey: .backgroundColor, or: fallback.backgroundColor),
            backgroundGradient: stored.value(forKey: .backgroundGradient, or: fallback.backgroundGradient),
            backgroundOpacity: stored.value(forKey: .backgroundOpacity, or: fallback.backgroundOpacity),
            backgroundHasShadow: stored.value(forKey: .backgroundHasShadow, or: fallback.backgroundHasShadow),
            backgroundHasBorder: stored.value(forKey: .backgroundHasBorder, or: fallback.backgroundHasBorder),
            backgroundBorderColor: stored.color(forKey: .backgroundBorderColor, or: fallback.backgroundBorderColor),
            backgroundBorderWidth: stored.value(forKey: .backgroundBorderWidth, or: fallback.backgroundBorderWidth),
            backgroundGlassStyle: stored.value(forKey: .backgroundGlassStyle, or: fallback.backgroundGlassStyle),
            tintGlassStyle: stored.value(forKey: .tintGlassStyle, or: fallback.tintGlassStyle),
            backgroundGlassIsColored: stored.value(forKey: .backgroundGlassIsColored, or: fallback.backgroundGlassIsColored),
            tintGlassIsColored: stored.value(forKey: .tintGlassIsColored, or: fallback.tintGlassIsColored),
            backgroundUsesAccentColor: stored.value(forKey: .backgroundUsesAccentColor, or: fallback.backgroundUsesAccentColor),
            tintUsesAccentColor: stored.value(forKey: .tintUsesAccentColor, or: fallback.tintUsesAccentColor),
            backgroundGlassFollowsSystem: stored.value(forKey: .backgroundGlassFollowsSystem, or: fallback.backgroundGlassFollowsSystem),
            tintGlassFollowsSystem: stored.value(forKey: .tintGlassFollowsSystem, or: fallback.tintGlassFollowsSystem),
            borderStyle: stored.value(forKey: .borderStyle, or: fallback.borderStyle)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(hasShadow, forKey: .hasShadow)
        try values.encode(hasBorder, forKey: .hasBorder)
        try values.encode(borderColor, forKey: .borderColor)
        try values.encode(borderWidth, forKey: .borderWidth)
        try values.encode(tintKind, forKey: .tintKind)
        try values.encode(tintColor, forKey: .tintColor)
        try values.encode(tintGradient, forKey: .tintGradient)
        try values.encode(tintOpacity, forKey: .tintOpacity)
        try values.encode(backgroundKind, forKey: .backgroundKind)
        try values.encode(backgroundColor, forKey: .backgroundColor)
        try values.encode(backgroundGradient, forKey: .backgroundGradient)
        try values.encode(backgroundOpacity, forKey: .backgroundOpacity)
        try values.encode(backgroundHasShadow, forKey: .backgroundHasShadow)
        try values.encode(backgroundHasBorder, forKey: .backgroundHasBorder)
        try values.encode(backgroundBorderColor, forKey: .backgroundBorderColor)
        try values.encode(backgroundBorderWidth, forKey: .backgroundBorderWidth)
        try values.encode(backgroundGlassStyle, forKey: .backgroundGlassStyle)
        try values.encode(tintGlassStyle, forKey: .tintGlassStyle)
        try values.encode(backgroundGlassIsColored, forKey: .backgroundGlassIsColored)
        try values.encode(tintGlassIsColored, forKey: .tintGlassIsColored)
        try values.encode(backgroundUsesAccentColor, forKey: .backgroundUsesAccentColor)
        try values.encode(tintUsesAccentColor, forKey: .tintUsesAccentColor)
        try values.encode(backgroundGlassFollowsSystem, forKey: .backgroundGlassFollowsSystem)
        try values.encode(tintGlassFollowsSystem, forKey: .tintGlassFollowsSystem)
        try values.encode(borderStyle, forKey: .borderStyle)
    }

    /// This configuration with every accent-following color set to accent.
    func withAccentColor(_ accent: CGColor) -> Self {
        var copy = self
        if copy.backgroundUsesAccentColor {
            copy.backgroundColor = accent
        }
        if copy.tintUsesAccentColor {
            copy.tintColor = accent
        }
        return copy
    }

    /// Sets system-following glass to Regular for Tinted or Clear for Clear.
    func withSystemGlass(tinted: Bool) -> Self {
        var copy = self
        let style: MenuBarGlassStyle = tinted ? .regular : .clear
        if copy.backgroundGlassFollowsSystem {
            copy.backgroundGlassStyle = style
        }
        if copy.tintGlassFollowsSystem {
            copy.tintGlassStyle = style
        }
        return copy
    }
}

// MARK: Coding Helpers

private nonisolated extension KeyedDecodingContainer {
    /// Decodes the value for key, substituting fallback when the key is
    /// absent or explicitly null.
    func value<Value: Decodable>(forKey key: Key, or fallback: Value) throws -> Value {
        try decodeIfPresent(Value.self, forKey: key) ?? fallback
    }

    /// Decodes a color stored in ThawColor's representation.
    func color(forKey key: Key, or fallback: CGColor) throws -> CGColor {
        try decodeIfPresent(ThawColor.self, forKey: key)?.cgColor ?? fallback
    }
}

private nonisolated extension KeyedEncodingContainer {
    /// Encodes a color in ThawColor's representation, matching color(forKey:or:).
    mutating func encode(_ color: CGColor, forKey key: Key) throws {
        try encode(ThawColor(cgColor: color), forKey: key)
    }
}

// MARK: - ResolvedThawBarAppearance

/// Resolves inheritance once so the renderer uses one consistent appearance.
nonisolated struct ResolvedThawBarAppearance: Hashable {
    var hasRoundedShape: Bool
    var fillConfiguration: MenuBarAppearancePartialConfiguration

    var hasShadow: Bool {
        fillConfiguration.hasShadow
    }

    var hasBorder: Bool {
        fillConfiguration.hasBorder
    }

    var borderColor: CGColor {
        fillConfiguration.borderColor
    }

    var borderWidth: Double {
        fillConfiguration.borderWidth
    }

    var tintKind: MenuBarTintKind {
        fillConfiguration.tintKind
    }

    var tintColor: CGColor {
        fillConfiguration.tintColor
    }

    var tintGradient: ThawGradient {
        fillConfiguration.tintGradient
    }

    var tintOpacity: Double {
        fillConfiguration.tintOpacity
    }

    var backgroundKind: MenuBarBackgroundKind {
        fillConfiguration.backgroundKind
    }

    var backgroundColor: CGColor {
        fillConfiguration.backgroundColor
    }

    var backgroundGradient: ThawGradient {
        fillConfiguration.backgroundGradient
    }

    var backgroundOpacity: Double {
        fillConfiguration.backgroundOpacity
    }

    var backgroundHasShadow: Bool {
        fillConfiguration.backgroundHasShadow
    }

    var backgroundHasBorder: Bool {
        fillConfiguration.backgroundHasBorder
    }

    var backgroundBorderColor: CGColor {
        fillConfiguration.backgroundBorderColor
    }

    var backgroundBorderWidth: Double {
        fillConfiguration.backgroundBorderWidth
    }

    var backgroundGlassStyle: MenuBarGlassStyle {
        fillConfiguration.backgroundGlassStyle
    }

    var tintGlassStyle: MenuBarGlassStyle {
        fillConfiguration.tintGlassStyle
    }

    var backgroundGlassIsColored: Bool {
        fillConfiguration.backgroundGlassIsColored
    }

    var tintGlassIsColored: Bool {
        fillConfiguration.tintGlassIsColored
    }
}

// MARK: - ThawBarAppearance

/// An optional, independently stored appearance for the floating bar.
nonisolated struct ThawBarAppearance: Hashable {
    var overridesMenuBar: Bool
    var hasRoundedShape: Bool
    var hasShadow: Bool
    var hasBorder: Bool
    var borderColor: CGColor
    var borderWidth: Double
    var tintKind: MenuBarTintKind
    var tintColor: CGColor
    var tintGradient: ThawGradient
    var tintOpacity: Double
    var backgroundKind: MenuBarBackgroundKind
    var backgroundColor: CGColor
    var backgroundGradient: ThawGradient
    var backgroundOpacity: Double
    var backgroundHasShadow: Bool
    var backgroundHasBorder: Bool
    var backgroundBorderColor: CGColor
    var backgroundBorderWidth: Double
    var backgroundGlassStyle: MenuBarGlassStyle
    var tintGlassStyle: MenuBarGlassStyle
    var backgroundGlassIsColored: Bool
    var tintGlassIsColored: Bool
    var backgroundUsesAccentColor = false
    var tintUsesAccentColor = false
    var backgroundGlassFollowsSystem = false
    var tintGlassFollowsSystem = false

    var fillConfiguration: MenuBarAppearancePartialConfiguration {
        get {
            MenuBarAppearancePartialConfiguration(
                hasShadow: hasShadow,
                hasBorder: hasBorder,
                borderColor: borderColor,
                borderWidth: borderWidth,
                tintKind: tintKind,
                tintColor: tintColor,
                tintGradient: tintGradient,
                tintOpacity: tintOpacity,
                backgroundKind: backgroundKind,
                backgroundColor: backgroundColor,
                backgroundGradient: backgroundGradient,
                backgroundOpacity: backgroundOpacity,
                backgroundHasShadow: backgroundHasShadow,
                backgroundHasBorder: backgroundHasBorder,
                backgroundBorderColor: backgroundBorderColor,
                backgroundBorderWidth: backgroundBorderWidth,
                backgroundGlassStyle: backgroundGlassStyle,
                tintGlassStyle: tintGlassStyle,
                backgroundGlassIsColored: backgroundGlassIsColored,
                tintGlassIsColored: tintGlassIsColored,
                backgroundUsesAccentColor: backgroundUsesAccentColor,
                tintUsesAccentColor: tintUsesAccentColor,
                backgroundGlassFollowsSystem: backgroundGlassFollowsSystem,
                tintGlassFollowsSystem: tintGlassFollowsSystem
            )
        }
        set {
            hasShadow = newValue.hasShadow
            hasBorder = newValue.hasBorder
            borderColor = newValue.borderColor
            borderWidth = newValue.borderWidth
            tintKind = newValue.tintKind
            tintColor = newValue.tintColor
            tintGradient = newValue.tintGradient
            tintOpacity = newValue.tintOpacity
            backgroundKind = newValue.backgroundKind
            backgroundColor = newValue.backgroundColor
            backgroundGradient = newValue.backgroundGradient
            backgroundOpacity = newValue.backgroundOpacity
            backgroundHasShadow = newValue.backgroundHasShadow
            backgroundHasBorder = newValue.backgroundHasBorder
            backgroundBorderColor = newValue.backgroundBorderColor
            backgroundBorderWidth = newValue.backgroundBorderWidth
            backgroundGlassStyle = newValue.backgroundGlassStyle
            tintGlassStyle = newValue.tintGlassStyle
            backgroundGlassIsColored = newValue.backgroundGlassIsColored
            tintGlassIsColored = newValue.tintGlassIsColored
            backgroundUsesAccentColor = newValue.backgroundUsesAccentColor
            tintUsesAccentColor = newValue.tintUsesAccentColor
            backgroundGlassFollowsSystem = newValue.backgroundGlassFollowsSystem
            tintGlassFollowsSystem = newValue.tintGlassFollowsSystem
        }
    }
}

nonisolated extension MenuBarAppearanceConfigurationV2 {
    /// This configuration with every accent-following color, in every mode
    /// and in the Thaw Bar's own look, set to accent.
    func withAccentColor(_ accent: CGColor) -> Self {
        var copy = self
        copy.staticConfiguration = copy.staticConfiguration.withAccentColor(accent)
        copy.lightModeConfiguration = copy.lightModeConfiguration.withAccentColor(accent)
        copy.darkModeConfiguration = copy.darkModeConfiguration.withAccentColor(accent)
        copy.thawBarAppearance.fillConfiguration = copy.thawBarAppearance.fillConfiguration.withAccentColor(accent)
        return copy
    }

    /// This configuration with every system-following glass style, in every
    /// mode and in the Thaw Bar's own look, set for the system setting.
    func withSystemGlass(tinted: Bool) -> Self {
        var copy = self
        copy.staticConfiguration = copy.staticConfiguration.withSystemGlass(tinted: tinted)
        copy.lightModeConfiguration = copy.lightModeConfiguration.withSystemGlass(tinted: tinted)
        copy.darkModeConfiguration = copy.darkModeConfiguration.withSystemGlass(tinted: tinted)
        copy.thawBarAppearance.fillConfiguration = copy.thawBarAppearance.fillConfiguration.withSystemGlass(tinted: tinted)
        return copy
    }
}

nonisolated extension ThawBarAppearance {
    static let defaultConfiguration = ThawBarAppearance(
        overridesMenuBar: false,
        hasRoundedShape: false,
        hasShadow: MenuBarAppearancePartialConfiguration.defaultConfiguration.hasShadow,
        hasBorder: MenuBarAppearancePartialConfiguration.defaultConfiguration.hasBorder,
        borderColor: MenuBarAppearancePartialConfiguration.defaultConfiguration.borderColor,
        borderWidth: MenuBarAppearancePartialConfiguration.defaultConfiguration.borderWidth,
        tintKind: MenuBarAppearancePartialConfiguration.defaultConfiguration.tintKind,
        tintColor: MenuBarAppearancePartialConfiguration.defaultConfiguration.tintColor,
        tintGradient: MenuBarAppearancePartialConfiguration.defaultConfiguration.tintGradient,
        tintOpacity: MenuBarAppearancePartialConfiguration.defaultConfiguration.tintOpacity,
        backgroundKind: MenuBarAppearancePartialConfiguration.defaultConfiguration.backgroundKind,
        backgroundColor: MenuBarAppearancePartialConfiguration.defaultConfiguration.backgroundColor,
        backgroundGradient: MenuBarAppearancePartialConfiguration.defaultConfiguration.backgroundGradient,
        backgroundOpacity: MenuBarAppearancePartialConfiguration.defaultConfiguration.backgroundOpacity,
        backgroundHasShadow: MenuBarAppearancePartialConfiguration.defaultConfiguration.backgroundHasShadow,
        backgroundHasBorder: MenuBarAppearancePartialConfiguration.defaultConfiguration.backgroundHasBorder,
        backgroundBorderColor: MenuBarAppearancePartialConfiguration.defaultConfiguration.backgroundBorderColor,
        backgroundBorderWidth: MenuBarAppearancePartialConfiguration.defaultConfiguration.backgroundBorderWidth,
        backgroundGlassStyle: MenuBarAppearancePartialConfiguration.defaultConfiguration.backgroundGlassStyle,
        tintGlassStyle: MenuBarAppearancePartialConfiguration.defaultConfiguration.tintGlassStyle,
        backgroundGlassIsColored: MenuBarAppearancePartialConfiguration.defaultConfiguration.backgroundGlassIsColored,
        tintGlassIsColored: MenuBarAppearancePartialConfiguration.defaultConfiguration.tintGlassIsColored
    )

    init(seededFrom resolved: ResolvedThawBarAppearance) {
        self = .defaultConfiguration
        overridesMenuBar = true
        hasRoundedShape = resolved.hasRoundedShape
        fillConfiguration = resolved.fillConfiguration
    }
}

nonisolated extension ThawBarAppearance: Codable {
    private enum CodingKeys: CodingKey {
        case overridesMenuBar
        case hasRoundedShape
        case hasShadow
        case hasBorder
        case borderColor
        case borderWidth
        case tintKind
        case tintColor
        case tintGradient
        case tintOpacity
        case backgroundKind
        case backgroundColor
        case backgroundGradient
        case backgroundOpacity
        case backgroundHasShadow
        case backgroundHasBorder
        case backgroundBorderColor
        case backgroundBorderWidth
        case backgroundGlassStyle
        case tintGlassStyle
        case backgroundGlassIsColored
        case tintGlassIsColored
        case backgroundUsesAccentColor
        case tintUsesAccentColor
        case backgroundGlassFollowsSystem
        case tintGlassFollowsSystem
    }

    init(from decoder: any Decoder) throws {
        let stored = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.defaultConfiguration
        try self.init(
            overridesMenuBar: stored.decodeIfPresent(Bool.self, forKey: .overridesMenuBar) ?? fallback.overridesMenuBar,
            hasRoundedShape: stored.decodeIfPresent(Bool.self, forKey: .hasRoundedShape) ?? fallback.hasRoundedShape,
            hasShadow: stored.value(forKey: .hasShadow, or: fallback.hasShadow),
            hasBorder: stored.value(forKey: .hasBorder, or: fallback.hasBorder),
            borderColor: stored.color(forKey: .borderColor, or: fallback.borderColor),
            borderWidth: stored.value(forKey: .borderWidth, or: fallback.borderWidth),
            tintKind: stored.value(forKey: .tintKind, or: fallback.tintKind),
            tintColor: stored.color(forKey: .tintColor, or: fallback.tintColor),
            tintGradient: stored.value(forKey: .tintGradient, or: fallback.tintGradient),
            tintOpacity: stored.value(forKey: .tintOpacity, or: fallback.tintOpacity),
            backgroundKind: stored.value(forKey: .backgroundKind, or: fallback.backgroundKind),
            backgroundColor: stored.color(forKey: .backgroundColor, or: fallback.backgroundColor),
            backgroundGradient: stored.value(forKey: .backgroundGradient, or: fallback.backgroundGradient),
            backgroundOpacity: stored.value(forKey: .backgroundOpacity, or: fallback.backgroundOpacity),
            backgroundHasShadow: stored.value(forKey: .backgroundHasShadow, or: fallback.backgroundHasShadow),
            backgroundHasBorder: stored.value(forKey: .backgroundHasBorder, or: fallback.backgroundHasBorder),
            backgroundBorderColor: stored.color(forKey: .backgroundBorderColor, or: fallback.backgroundBorderColor),
            backgroundBorderWidth: stored.value(forKey: .backgroundBorderWidth, or: fallback.backgroundBorderWidth),
            backgroundGlassStyle: stored.value(forKey: .backgroundGlassStyle, or: fallback.backgroundGlassStyle),
            tintGlassStyle: stored.value(forKey: .tintGlassStyle, or: fallback.tintGlassStyle),
            backgroundGlassIsColored: stored.value(forKey: .backgroundGlassIsColored, or: fallback.backgroundGlassIsColored),
            tintGlassIsColored: stored.value(forKey: .tintGlassIsColored, or: fallback.tintGlassIsColored),
            backgroundUsesAccentColor: stored.value(forKey: .backgroundUsesAccentColor, or: fallback.backgroundUsesAccentColor),
            tintUsesAccentColor: stored.value(forKey: .tintUsesAccentColor, or: fallback.tintUsesAccentColor),
            backgroundGlassFollowsSystem: stored.value(forKey: .backgroundGlassFollowsSystem, or: fallback.backgroundGlassFollowsSystem),
            tintGlassFollowsSystem: stored.value(forKey: .tintGlassFollowsSystem, or: fallback.tintGlassFollowsSystem)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(overridesMenuBar, forKey: .overridesMenuBar)
        try values.encode(hasRoundedShape, forKey: .hasRoundedShape)
        try values.encode(hasShadow, forKey: .hasShadow)
        try values.encode(hasBorder, forKey: .hasBorder)
        try values.encode(borderColor, forKey: .borderColor)
        try values.encode(borderWidth, forKey: .borderWidth)
        try values.encode(tintKind, forKey: .tintKind)
        try values.encode(tintColor, forKey: .tintColor)
        try values.encode(tintGradient, forKey: .tintGradient)
        try values.encode(tintOpacity, forKey: .tintOpacity)
        try values.encode(backgroundKind, forKey: .backgroundKind)
        try values.encode(backgroundColor, forKey: .backgroundColor)
        try values.encode(backgroundGradient, forKey: .backgroundGradient)
        try values.encode(backgroundOpacity, forKey: .backgroundOpacity)
        try values.encode(backgroundHasShadow, forKey: .backgroundHasShadow)
        try values.encode(backgroundHasBorder, forKey: .backgroundHasBorder)
        try values.encode(backgroundBorderColor, forKey: .backgroundBorderColor)
        try values.encode(backgroundBorderWidth, forKey: .backgroundBorderWidth)
        try values.encode(backgroundGlassStyle, forKey: .backgroundGlassStyle)
        try values.encode(tintGlassStyle, forKey: .tintGlassStyle)
        try values.encode(backgroundGlassIsColored, forKey: .backgroundGlassIsColored)
        try values.encode(tintGlassIsColored, forKey: .tintGlassIsColored)
        try values.encode(backgroundUsesAccentColor, forKey: .backgroundUsesAccentColor)
        try values.encode(tintUsesAccentColor, forKey: .tintUsesAccentColor)
        try values.encode(backgroundGlassFollowsSystem, forKey: .backgroundGlassFollowsSystem)
        try values.encode(tintGlassFollowsSystem, forKey: .tintGlassFollowsSystem)
    }
}
