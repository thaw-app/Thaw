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
    var shapeKind: MenuBarShapeKind
    var fullShapeInfo: MenuBarFullShapeInfo
    var splitShapeInfo: MenuBarSplitShapeInfo
    var notchShapeInfo: MenuBarNotchShapeInfo
    var isInset: Bool
    var leftMargin: Double
    var rightMargin: Double
    var notchMargin: Double
    var isDynamic: Bool
    /// The Thaw Bar's own appearance, honoured only when it opts in.
    var thawBarAppearance: ThawBarAppearance

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

    /// The values the Thaw Bar draws with, from whichever side owns them.
    ///
    /// The override is all or nothing. Letting it win field by field would
    /// mean a panel that is half its own colour and half the menu bar's, and
    /// there is no editor gesture that asks for that.
    @MainActor
    var resolvedThawBarAppearance: ResolvedThawBarAppearance {
        let partial = current
        guard thawBarAppearance.overridesMenuBar else {
            return ResolvedThawBarAppearance(
                hasRoundedShape: hasRoundedShape,
                tintKind: partial.tintKind,
                tintColor: partial.tintColor,
                tintGradient: partial.tintGradient,
                // Not `partial.tintOpacity`. The Thaw Bar has always drawn the
                // inherited tint at a fixed opacity, so reading the menu bar's
                // here would restyle every existing install.
                tintOpacity: ThawBarAppearance.inheritedTintOpacity,
                hasBorder: partial.borderOnThawBar,
                borderColor: partial.borderColor,
                borderWidth: partial.borderWidth
            )
        }
        return ResolvedThawBarAppearance(
            hasRoundedShape: thawBarAppearance.hasRoundedShape,
            tintKind: thawBarAppearance.tintKind,
            tintColor: thawBarAppearance.tintColor,
            tintGradient: thawBarAppearance.tintGradient,
            tintOpacity: thawBarAppearance.tintOpacity,
            hasBorder: thawBarAppearance.hasBorder,
            borderColor: thawBarAppearance.borderColor,
            borderWidth: thawBarAppearance.borderWidth
        )
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
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            lightModeConfiguration: container.decodeIfPresent(MenuBarAppearancePartialConfiguration.self, forKey: .lightModeConfiguration) ?? Self.defaultConfiguration.lightModeConfiguration,
            darkModeConfiguration: container.decodeIfPresent(MenuBarAppearancePartialConfiguration.self, forKey: .darkModeConfiguration) ?? Self.defaultConfiguration.darkModeConfiguration,
            staticConfiguration: container.decodeIfPresent(MenuBarAppearancePartialConfiguration.self, forKey: .staticConfiguration) ?? Self.defaultConfiguration.staticConfiguration,
            shapeKind: container.decodeIfPresent(MenuBarShapeKind.self, forKey: .shapeKind) ?? Self.defaultConfiguration.shapeKind,
            fullShapeInfo: container.decodeIfPresent(MenuBarFullShapeInfo.self, forKey: .fullShapeInfo) ?? Self.defaultConfiguration.fullShapeInfo,
            splitShapeInfo: container.decodeIfPresent(MenuBarSplitShapeInfo.self, forKey: .splitShapeInfo) ?? Self.defaultConfiguration.splitShapeInfo,
            notchShapeInfo: container.decodeIfPresent(MenuBarNotchShapeInfo.self, forKey: .notchShapeInfo) ?? Self.defaultConfiguration.notchShapeInfo,
            isInset: container.decodeIfPresent(Bool.self, forKey: .isInset) ?? Self.defaultConfiguration.isInset,
            leftMargin: container.decodeIfPresent(Double.self, forKey: .leftMargin) ?? Self.defaultConfiguration.leftMargin,
            rightMargin: container.decodeIfPresent(Double.self, forKey: .rightMargin) ?? Self.defaultConfiguration.rightMargin,
            notchMargin: container.decodeIfPresent(Double.self, forKey: .notchMargin) ?? Self.defaultConfiguration.notchMargin,
            isDynamic: container.decodeIfPresent(Bool.self, forKey: .isDynamic) ?? Self.defaultConfiguration.isDynamic,
            thawBarAppearance: container.decodeIfPresent(ThawBarAppearance.self, forKey: .thawBarAppearance) ?? Self.defaultConfiguration.thawBarAppearance
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lightModeConfiguration, forKey: .lightModeConfiguration)
        try container.encode(darkModeConfiguration, forKey: .darkModeConfiguration)
        try container.encode(staticConfiguration, forKey: .staticConfiguration)
        try container.encode(shapeKind, forKey: .shapeKind)
        try container.encode(fullShapeInfo, forKey: .fullShapeInfo)
        try container.encode(splitShapeInfo, forKey: .splitShapeInfo)
        try container.encode(notchShapeInfo, forKey: .notchShapeInfo)
        try container.encode(isInset, forKey: .isInset)
        try container.encode(leftMargin, forKey: .leftMargin)
        try container.encode(rightMargin, forKey: .rightMargin)
        try container.encode(notchMargin, forKey: .notchMargin)
        try container.encode(isDynamic, forKey: .isDynamic)
        try container.encode(thawBarAppearance, forKey: .thawBarAppearance)
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

// MARK: - ThawBarAppearance

/// The Thaw Bar's own appearance, drawn in place of the menu bar's when
/// ``overridesMenuBar`` is set.
///
/// The Thaw Bar has always borrowed the menu bar's shape, tint and border so
/// the two read as one surface. That stays the default: every field here is
/// ignored until the user opts in, and the values seeded into a fresh
/// override are the ones the panel was already drawing with, so enabling it
/// changes nothing until something is edited.
///
/// Only the corner treatment carries over from ``MenuBarShapeKind``. The
/// shape kinds describe where the menu bar overlay starts and stops, which a
/// floating panel has no equivalent of.
nonisolated struct ThawBarAppearance: Hashable {
    /// Whether the Thaw Bar draws with these values instead of the menu bar's.
    var overridesMenuBar: Bool
    /// Whether the panel's corners are fully rounded rather than squircled.
    var hasRoundedShape: Bool
    var tintKind: MenuBarTintKind
    var tintColor: CGColor
    var tintGradient: IceGradient
    var tintOpacity: Double
    var hasBorder: Bool
    var borderColor: CGColor
    var borderWidth: Double
}

// MARK: Default ThawBarAppearance

nonisolated extension ThawBarAppearance {
    /// The opacity the Thaw Bar has always drawn its inherited tint at.
    ///
    /// `MenuBarItemContainer` hardcoded this, so an override seeded from the
    /// menu bar's own `tintOpacity` would shift the panel the moment it was
    /// switched on. Seeding from this value is what keeps the opt-in inert.
    static let inheritedTintOpacity: Double = 0.2

    static let defaultConfiguration = ThawBarAppearance(
        overridesMenuBar: false,
        hasRoundedShape: false,
        tintKind: .solid,
        tintColor: .black,
        tintGradient: .defaultMenuBarTint,
        tintOpacity: inheritedTintOpacity,
        hasBorder: false,
        borderColor: .black,
        borderWidth: 1
    )
}

// MARK: Seeding an Override

nonisolated extension ThawBarAppearance {
    /// The tint kinds the Thaw Bar can draw.
    ///
    /// Glass and the two wallpaper-derived kinds are handled by the menu bar
    /// overlay, which composites against a live backdrop. The panel has no
    /// equivalent path and has always drawn nothing for them, so offering them
    /// here would be an editor control with no effect.
    static let supportedTintKinds: [MenuBarTintKind] = [.noTint, .solid, .gradient]

    /// An override seeded from what the Thaw Bar is drawing right now.
    ///
    /// Switching the override on should not move anything on screen, so it
    /// starts from the resolved values rather than from the defaults. A tint
    /// kind the panel cannot draw comes across as ``MenuBarTintKind/noTint``,
    /// which is what it was already showing for that kind anyway.
    init(seededFrom resolved: ResolvedThawBarAppearance) {
        self.init(
            overridesMenuBar: true,
            hasRoundedShape: resolved.hasRoundedShape,
            tintKind: Self.supportedTintKinds.contains(resolved.tintKind) ? resolved.tintKind : .noTint,
            tintColor: resolved.tintColor,
            tintGradient: resolved.tintGradient,
            tintOpacity: resolved.tintOpacity,
            hasBorder: resolved.hasBorder,
            borderColor: resolved.borderColor,
            borderWidth: resolved.borderWidth
        )
    }
}

// MARK: ThawBarAppearance: Codable

nonisolated extension ThawBarAppearance: Codable {
    private enum CodingKeys: CodingKey {
        case overridesMenuBar
        case hasRoundedShape
        case tintKind
        case tintColor
        case tintGradient
        case tintOpacity
        case hasBorder
        case borderColor
        case borderWidth
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            overridesMenuBar: container.decodeIfPresent(Bool.self, forKey: .overridesMenuBar) ?? Self.defaultConfiguration.overridesMenuBar,
            hasRoundedShape: container.decodeIfPresent(Bool.self, forKey: .hasRoundedShape) ?? Self.defaultConfiguration.hasRoundedShape,
            tintKind: container.decodeIfPresent(MenuBarTintKind.self, forKey: .tintKind) ?? Self.defaultConfiguration.tintKind,
            tintColor: container.decodeIfPresent(IceColor.self, forKey: .tintColor)?.cgColor ?? Self.defaultConfiguration.tintColor,
            tintGradient: container.decodeIfPresent(IceGradient.self, forKey: .tintGradient) ?? Self.defaultConfiguration.tintGradient,
            tintOpacity: container.decodeIfPresent(Double.self, forKey: .tintOpacity) ?? Self.defaultConfiguration.tintOpacity,
            hasBorder: container.decodeIfPresent(Bool.self, forKey: .hasBorder) ?? Self.defaultConfiguration.hasBorder,
            borderColor: container.decodeIfPresent(IceColor.self, forKey: .borderColor)?.cgColor ?? Self.defaultConfiguration.borderColor,
            borderWidth: container.decodeIfPresent(Double.self, forKey: .borderWidth) ?? Self.defaultConfiguration.borderWidth
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(overridesMenuBar, forKey: .overridesMenuBar)
        try container.encode(hasRoundedShape, forKey: .hasRoundedShape)
        try container.encode(tintKind, forKey: .tintKind)
        try container.encode(IceColor(cgColor: tintColor), forKey: .tintColor)
        try container.encode(tintGradient, forKey: .tintGradient)
        try container.encode(tintOpacity, forKey: .tintOpacity)
        try container.encode(hasBorder, forKey: .hasBorder)
        try container.encode(IceColor(cgColor: borderColor), forKey: .borderColor)
        try container.encode(borderWidth, forKey: .borderWidth)
    }
}

// MARK: - ResolvedThawBarAppearance

/// The values the Thaw Bar actually draws with, after the override has been
/// weighed against the menu bar's configuration.
///
/// Resolving in one place keeps the "which side won?" question out of the
/// view, which otherwise has to ask it separately for the shape, the tint and
/// the border and can answer inconsistently.
nonisolated struct ResolvedThawBarAppearance: Hashable {
    var hasRoundedShape: Bool
    var tintKind: MenuBarTintKind
    var tintColor: CGColor
    var tintGradient: IceGradient
    var tintOpacity: Double
    var hasBorder: Bool
    var borderColor: CGColor
    var borderWidth: Double
}
