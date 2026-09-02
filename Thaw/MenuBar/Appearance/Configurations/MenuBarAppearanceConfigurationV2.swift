//
//  MenuBarAppearanceConfigurationV2.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

nonisolated struct MenuBarAppearanceConfigurationV2: Hashable {
    var lightModeConfiguration: MenuBarAppearancePartialConfiguration
    var darkModeConfiguration: MenuBarAppearancePartialConfiguration
    var staticConfiguration: MenuBarAppearancePartialConfiguration
    /// Thaw Bar appearance for light mode when ``isDynamic`` is on.
    var thawBarLightModeConfiguration: ThawBarAppearancePartialConfiguration
    /// Thaw Bar appearance for dark mode when ``isDynamic`` is on.
    var thawBarDarkModeConfiguration: ThawBarAppearancePartialConfiguration
    /// Thaw Bar appearance when ``isDynamic`` is off.
    var thawBarStaticConfiguration: ThawBarAppearancePartialConfiguration
    var shapeKind: MenuBarShapeKind
    var fullShapeInfo: MenuBarFullShapeInfo
    var splitShapeInfo: MenuBarSplitShapeInfo
    var notchShapeInfo: MenuBarNotchShapeInfo
    var isInset: Bool
    var leftMargin: Double
    var rightMargin: Double
    var notchMargin: Double
    var isDynamic: Bool

    var hasRoundedShape: Bool {
        switch shapeKind {
        case .noShape: false
        case .full: fullShapeInfo.hasRoundedShape
        case .split: splitShapeInfo.hasRoundedShape
        case .notch: notchShapeInfo.hasRoundedShape
        }
    }

    @MainActor
    var current: MenuBarAppearancePartialConfiguration {
        if isDynamic {
            switch SystemAppearance.current {
            case .light: lightModeConfiguration
            case .dark: darkModeConfiguration
            }
        } else {
            staticConfiguration
        }
    }

    /// The Thaw Bar partial that applies under the current system appearance.
    @MainActor
    var currentThawBar: ThawBarAppearancePartialConfiguration {
        if isDynamic {
            switch SystemAppearance.current {
            case .light: thawBarLightModeConfiguration
            case .dark: thawBarDarkModeConfiguration
            }
        } else {
            thawBarStaticConfiguration
        }
    }
}

// MARK: Default Configuration

nonisolated extension MenuBarAppearanceConfigurationV2 {
    static let defaultConfiguration = MenuBarAppearanceConfigurationV2(
        lightModeConfiguration: .defaultConfiguration,
        darkModeConfiguration: .defaultConfiguration,
        staticConfiguration: .defaultConfiguration,
        thawBarLightModeConfiguration: .defaultConfiguration,
        thawBarDarkModeConfiguration: .defaultConfiguration,
        thawBarStaticConfiguration: .defaultConfiguration,
        shapeKind: .noShape,
        fullShapeInfo: .defaultValue,
        splitShapeInfo: .defaultValue,
        notchShapeInfo: .defaultValue,
        isInset: true,
        leftMargin: 0,
        rightMargin: 0,
        notchMargin: 0,
        isDynamic: false
    )
}

nonisolated extension MenuBarAppearanceConfigurationV2: Codable {
    private enum CodingKeys: CodingKey {
        case lightModeConfiguration
        case darkModeConfiguration
        case staticConfiguration
        case thawBarLightModeConfiguration
        case thawBarDarkModeConfiguration
        case thawBarStaticConfiguration
        case shapeKind
        case fullShapeInfo
        case splitShapeInfo
        case notchShapeInfo
        case isInset
        case leftMargin
        case rightMargin
        case notchMargin
        case isDynamic
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let light = try container.decodeIfPresent(MenuBarAppearancePartialConfiguration.self, forKey: .lightModeConfiguration) ?? Self.defaultConfiguration.lightModeConfiguration
        let dark = try container.decodeIfPresent(MenuBarAppearancePartialConfiguration.self, forKey: .darkModeConfiguration) ?? Self.defaultConfiguration.darkModeConfiguration
        let staticPartial = try container.decodeIfPresent(MenuBarAppearancePartialConfiguration.self, forKey: .staticConfiguration) ?? Self.defaultConfiguration.staticConfiguration

        // Pre-Thaw-Bar-appearance payloads have no thawBar* keys. Seed each
        // slot from the matching menu bar partial so borders carry over and
        // the historical black tint overlay is cleared (see migrating(from:)).
        let thawBarLight = try container.decodeIfPresent(ThawBarAppearancePartialConfiguration.self, forKey: .thawBarLightModeConfiguration)
            ?? .migrating(from: light)
        let thawBarDark = try container.decodeIfPresent(ThawBarAppearancePartialConfiguration.self, forKey: .thawBarDarkModeConfiguration)
            ?? .migrating(from: dark)
        let thawBarStatic = try container.decodeIfPresent(ThawBarAppearancePartialConfiguration.self, forKey: .thawBarStaticConfiguration)
            ?? .migrating(from: staticPartial)

        try self.init(
            lightModeConfiguration: light,
            darkModeConfiguration: dark,
            staticConfiguration: staticPartial,
            thawBarLightModeConfiguration: thawBarLight,
            thawBarDarkModeConfiguration: thawBarDark,
            thawBarStaticConfiguration: thawBarStatic,
            shapeKind: container.decodeIfPresent(MenuBarShapeKind.self, forKey: .shapeKind) ?? Self.defaultConfiguration.shapeKind,
            fullShapeInfo: container.decodeIfPresent(MenuBarFullShapeInfo.self, forKey: .fullShapeInfo) ?? Self.defaultConfiguration.fullShapeInfo,
            splitShapeInfo: container.decodeIfPresent(MenuBarSplitShapeInfo.self, forKey: .splitShapeInfo) ?? Self.defaultConfiguration.splitShapeInfo,
            notchShapeInfo: container.decodeIfPresent(MenuBarNotchShapeInfo.self, forKey: .notchShapeInfo) ?? Self.defaultConfiguration.notchShapeInfo,
            isInset: container.decodeIfPresent(Bool.self, forKey: .isInset) ?? Self.defaultConfiguration.isInset,
            leftMargin: container.decodeIfPresent(Double.self, forKey: .leftMargin) ?? Self.defaultConfiguration.leftMargin,
            rightMargin: container.decodeIfPresent(Double.self, forKey: .rightMargin) ?? Self.defaultConfiguration.rightMargin,
            notchMargin: container.decodeIfPresent(Double.self, forKey: .notchMargin) ?? Self.defaultConfiguration.notchMargin,
            isDynamic: container.decodeIfPresent(Bool.self, forKey: .isDynamic) ?? Self.defaultConfiguration.isDynamic
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lightModeConfiguration, forKey: .lightModeConfiguration)
        try container.encode(darkModeConfiguration, forKey: .darkModeConfiguration)
        try container.encode(staticConfiguration, forKey: .staticConfiguration)
        try container.encode(thawBarLightModeConfiguration, forKey: .thawBarLightModeConfiguration)
        try container.encode(thawBarDarkModeConfiguration, forKey: .thawBarDarkModeConfiguration)
        try container.encode(thawBarStaticConfiguration, forKey: .thawBarStaticConfiguration)
        try container.encode(shapeKind, forKey: .shapeKind)
        try container.encode(fullShapeInfo, forKey: .fullShapeInfo)
        try container.encode(splitShapeInfo, forKey: .splitShapeInfo)
        try container.encode(notchShapeInfo, forKey: .notchShapeInfo)
        try container.encode(isInset, forKey: .isInset)
        try container.encode(leftMargin, forKey: .leftMargin)
        try container.encode(rightMargin, forKey: .rightMargin)
        try container.encode(notchMargin, forKey: .notchMargin)
        try container.encode(isDynamic, forKey: .isDynamic)
    }
}

// MARK: - MenuBarAppearancePartialConfiguration

nonisolated struct MenuBarAppearancePartialConfiguration: Hashable {
    var hasShadow: Bool
    /// Whether the shape border is drawn around the menu bar overlay.
    var borderOnMenuBar: Bool
    /// Whether the shape border is drawn around the Thaw Bar.
    ///
    /// The Thaw Bar is the panel in `IceBar.swift`, which still carries the
    /// `iceBar` prefix from Ice on everything that is persisted under an
    /// existing defaults key. This one is new, so it uses the current name.
    var borderOnThawBar: Bool
    var borderColor: CGColor
    var borderWidth: Double
    var tintKind: MenuBarTintKind
    var tintColor: CGColor
    var tintGradient: IceGradient
    var tintOpacity: Double
    var backgroundKind: MenuBarBackgroundKind
    var backgroundColor: CGColor
    var backgroundGradient: IceGradient
    var backgroundOpacity: Double
    var backgroundHasShadow: Bool
    var backgroundHasBorder: Bool
    var backgroundBorderColor: CGColor
    var backgroundBorderWidth: Double
    var backgroundGlassStyle: MenuBarGlassStyle
    var tintGlassStyle: MenuBarGlassStyle

    /// Whether the shape border is drawn anywhere.
    ///
    /// Setting this turns the border on or off in both places at once, which
    /// is what every caller predating the split means by it: the Ice import
    /// in ``MenuBarAppearanceConfigurationV2/init(migrating:)`` carries over
    /// a single flag, and the editor uses it to decide whether the colour and
    /// width rows apply to anything at all.
    var hasBorder: Bool {
        get {
            borderOnMenuBar || borderOnThawBar
        }
        set {
            borderOnMenuBar = newValue
            borderOnThawBar = newValue
        }
    }
}

// MARK: Default Partial Configuration

nonisolated extension MenuBarAppearancePartialConfiguration {
    static let defaultConfiguration = MenuBarAppearancePartialConfiguration(
        hasShadow: false,
        borderOnMenuBar: false,
        borderOnThawBar: false,
        borderColor: .black,
        borderWidth: 1,
        tintKind: .solid,
        tintColor: .black,
        tintGradient: .defaultMenuBarTint,
        tintOpacity: 0.2,
        backgroundKind: .defaultKind,
        backgroundColor: .black,
        backgroundGradient: .defaultMenuBarTint,
        backgroundOpacity: 0.2,
        backgroundHasShadow: false,
        backgroundHasBorder: false,
        backgroundBorderColor: .black,
        backgroundBorderWidth: 1,
        backgroundGlassStyle: .regular,
        tintGlassStyle: .regular
    )
}

// MARK: MenuBarAppearancePartialConfiguration: Codable

nonisolated extension MenuBarAppearancePartialConfiguration: Codable {
    private enum CodingKeys: CodingKey {
        case hasShadow
        /// The single border flag that predates the menu bar / Thaw Bar split.
        ///
        /// Still written on encode so that settings stay readable if the user
        /// moves back to a build that only knows about this key.
        case hasBorder
        case borderOnMenuBar
        case borderOnThawBar
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Settings written before the split only carry `hasBorder`, which applied
        // to the menu bar and the Thaw Bar at once, so it seeds both flags.
        let legacyHasBorder = try container.decodeIfPresent(Bool.self, forKey: .hasBorder)
        try self.init(
            hasShadow: container.decodeIfPresent(Bool.self, forKey: .hasShadow) ?? Self.defaultConfiguration.hasShadow,
            borderOnMenuBar: container.decodeIfPresent(Bool.self, forKey: .borderOnMenuBar) ?? legacyHasBorder ?? Self.defaultConfiguration.borderOnMenuBar,
            borderOnThawBar: container.decodeIfPresent(Bool.self, forKey: .borderOnThawBar) ?? legacyHasBorder ?? Self.defaultConfiguration.borderOnThawBar,
            borderColor: container.decodeIfPresent(IceColor.self, forKey: .borderColor)?.cgColor ?? Self.defaultConfiguration.borderColor,
            borderWidth: container.decodeIfPresent(Double.self, forKey: .borderWidth) ?? Self.defaultConfiguration.borderWidth,
            tintKind: container.decodeIfPresent(MenuBarTintKind.self, forKey: .tintKind) ?? Self.defaultConfiguration.tintKind,
            tintColor: container.decodeIfPresent(IceColor.self, forKey: .tintColor)?.cgColor ?? Self.defaultConfiguration.tintColor,
            tintGradient: container.decodeIfPresent(IceGradient.self, forKey: .tintGradient) ?? Self.defaultConfiguration.tintGradient,
            tintOpacity: container.decodeIfPresent(Double.self, forKey: .tintOpacity) ?? Self.defaultConfiguration.tintOpacity,
            backgroundKind: container.decodeIfPresent(MenuBarBackgroundKind.self, forKey: .backgroundKind) ?? Self.defaultConfiguration.backgroundKind,
            backgroundColor: container.decodeIfPresent(IceColor.self, forKey: .backgroundColor)?.cgColor ?? Self.defaultConfiguration.backgroundColor,
            backgroundGradient: container.decodeIfPresent(IceGradient.self, forKey: .backgroundGradient) ?? Self.defaultConfiguration.backgroundGradient,
            backgroundOpacity: container.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? Self.defaultConfiguration.backgroundOpacity,
            backgroundHasShadow: container.decodeIfPresent(Bool.self, forKey: .backgroundHasShadow) ?? Self.defaultConfiguration.backgroundHasShadow,
            backgroundHasBorder: container.decodeIfPresent(Bool.self, forKey: .backgroundHasBorder) ?? Self.defaultConfiguration.backgroundHasBorder,
            backgroundBorderColor: container.decodeIfPresent(IceColor.self, forKey: .backgroundBorderColor)?.cgColor ?? Self.defaultConfiguration.backgroundBorderColor,
            backgroundBorderWidth: container.decodeIfPresent(Double.self, forKey: .backgroundBorderWidth) ?? Self.defaultConfiguration.backgroundBorderWidth,
            backgroundGlassStyle: container.decodeIfPresent(MenuBarGlassStyle.self, forKey: .backgroundGlassStyle) ?? Self.defaultConfiguration.backgroundGlassStyle,
            tintGlassStyle: container.decodeIfPresent(MenuBarGlassStyle.self, forKey: .tintGlassStyle) ?? Self.defaultConfiguration.tintGlassStyle
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hasShadow, forKey: .hasShadow)
        try container.encode(hasBorder, forKey: .hasBorder)
        try container.encode(borderOnMenuBar, forKey: .borderOnMenuBar)
        try container.encode(borderOnThawBar, forKey: .borderOnThawBar)
        try container.encode(IceColor(cgColor: borderColor), forKey: .borderColor)
        try container.encode(borderWidth, forKey: .borderWidth)
        try container.encode(tintKind, forKey: .tintKind)
        try container.encode(IceColor(cgColor: tintColor), forKey: .tintColor)
        try container.encode(tintGradient, forKey: .tintGradient)
        try container.encode(tintOpacity, forKey: .tintOpacity)
        try container.encode(backgroundKind, forKey: .backgroundKind)
        try container.encode(IceColor(cgColor: backgroundColor), forKey: .backgroundColor)
        try container.encode(backgroundGradient, forKey: .backgroundGradient)
        try container.encode(backgroundOpacity, forKey: .backgroundOpacity)
        try container.encode(backgroundHasShadow, forKey: .backgroundHasShadow)
        try container.encode(backgroundHasBorder, forKey: .backgroundHasBorder)
        try container.encode(IceColor(cgColor: backgroundBorderColor), forKey: .backgroundBorderColor)
        try container.encode(backgroundBorderWidth, forKey: .backgroundBorderWidth)
        try container.encode(backgroundGlassStyle, forKey: .backgroundGlassStyle)
        try container.encode(tintGlassStyle, forKey: .tintGlassStyle)
    }
}
