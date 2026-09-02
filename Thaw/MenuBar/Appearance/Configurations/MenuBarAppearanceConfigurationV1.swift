//
//  MenuBarAppearanceConfigurationV1.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Configuration for the menu bar's appearance, as Ice stored it before its
/// `0.11.10` release.
///
/// Thaw never wrote this format. It exists to decode appearance data that
/// ``IceSettingsImporter`` finds in an old Ice install, which it converts with
/// ``MenuBarAppearanceConfigurationV2/init(migrating:)``.
struct MenuBarAppearanceConfigurationV1: Hashable {
    var hasShadow: Bool
    var hasBorder: Bool
    var isInset: Bool
    var borderColor: CGColor
    var borderWidth: Double
    var shapeKind: MenuBarShapeKind
    var fullShapeInfo: MenuBarFullShapeInfo
    var splitShapeInfo: MenuBarSplitShapeInfo
    var tintKind: MenuBarTintKind
    var tintColor: CGColor
    var tintGradient: IceGradient

    var hasRoundedShape: Bool {
        switch shapeKind {
        case .noShape: false
        case .full: fullShapeInfo.hasRoundedShape
        case .split: splitShapeInfo.hasRoundedShape
        case .notch: false
        }
    }
}

// MARK: Default Configuration

extension MenuBarAppearanceConfigurationV1 {
    static let defaultConfiguration = MenuBarAppearanceConfigurationV1(
        hasShadow: false,
        hasBorder: false,
        isInset: true,
        borderColor: .black,
        borderWidth: 1,
        shapeKind: .noShape,
        fullShapeInfo: .defaultValue,
        splitShapeInfo: .defaultValue,
        tintKind: .noTint,
        tintColor: .black,
        tintGradient: .defaultMenuBarTint
    )
}

// MARK: - Conversion to the Current Configuration

extension MenuBarAppearanceConfigurationV2 {
    /// Creates a configuration from a V1 configuration, which is the format
    /// Ice used before its `0.11.10` release.
    ///
    /// V1 had a single set of appearance values rather than one per system
    /// appearance, so the old values are applied to all three of the current
    /// configuration's slots. Values V1 had no equivalent for keep their
    /// defaults.
    init(migrating oldConfiguration: MenuBarAppearanceConfigurationV1) {
        self = withMutableCopy(of: Self.defaultConfiguration) { configuration in
            let partialConfiguration = withMutableCopy(
                of: MenuBarAppearancePartialConfiguration.defaultConfiguration
            ) { partial in
                partial.hasShadow = oldConfiguration.hasShadow
                partial.hasBorder = oldConfiguration.hasBorder
                partial.borderColor = oldConfiguration.borderColor
                partial.borderWidth = oldConfiguration.borderWidth
                partial.tintKind = oldConfiguration.tintKind
                partial.tintColor = oldConfiguration.tintColor
                partial.tintGradient = oldConfiguration.tintGradient
            }
            configuration.lightModeConfiguration = partialConfiguration
            configuration.darkModeConfiguration = partialConfiguration
            configuration.staticConfiguration = partialConfiguration
            let thawBarPartial = ThawBarAppearancePartialConfiguration.migrating(from: partialConfiguration)
            configuration.thawBarLightModeConfiguration = thawBarPartial
            configuration.thawBarDarkModeConfiguration = thawBarPartial
            configuration.thawBarStaticConfiguration = thawBarPartial
            configuration.shapeKind = oldConfiguration.shapeKind
            configuration.fullShapeInfo = oldConfiguration.fullShapeInfo
            configuration.splitShapeInfo = oldConfiguration.splitShapeInfo
            configuration.isInset = oldConfiguration.isInset
        }
    }
}

// MARK: MenuBarAppearanceConfigurationV1: Codable

extension MenuBarAppearanceConfigurationV1: Codable {
    private enum CodingKeys: CodingKey {
        case hasShadow
        case hasBorder
        case isInset
        case borderColor
        case borderWidth
        case shapeKind
        case fullShapeInfo
        case splitShapeInfo
        case tintKind
        case tintColor
        case tintGradient
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            hasShadow: container.decodeIfPresent(Bool.self, forKey: .hasShadow) ?? Self.defaultConfiguration.hasShadow,
            hasBorder: container.decodeIfPresent(Bool.self, forKey: .hasBorder) ?? Self.defaultConfiguration.hasBorder,
            isInset: container.decodeIfPresent(Bool.self, forKey: .isInset) ?? Self.defaultConfiguration.isInset,
            borderColor: container.decodeIfPresent(IceColor.self, forKey: .borderColor)?.cgColor ?? Self.defaultConfiguration.borderColor,
            borderWidth: container.decodeIfPresent(Double.self, forKey: .borderWidth) ?? Self.defaultConfiguration.borderWidth,
            shapeKind: container.decodeIfPresent(MenuBarShapeKind.self, forKey: .shapeKind) ?? Self.defaultConfiguration.shapeKind,
            fullShapeInfo: container.decodeIfPresent(MenuBarFullShapeInfo.self, forKey: .fullShapeInfo) ?? Self.defaultConfiguration.fullShapeInfo,
            splitShapeInfo: container.decodeIfPresent(MenuBarSplitShapeInfo.self, forKey: .splitShapeInfo) ?? Self.defaultConfiguration.splitShapeInfo,
            tintKind: container.decodeIfPresent(MenuBarTintKind.self, forKey: .tintKind) ?? Self.defaultConfiguration.tintKind,
            tintColor: container.decodeIfPresent(IceColor.self, forKey: .tintColor)?.cgColor ?? Self.defaultConfiguration.tintColor,
            tintGradient: container.decodeIfPresent(IceGradient.self, forKey: .tintGradient) ?? Self.defaultConfiguration.tintGradient
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hasShadow, forKey: .hasShadow)
        try container.encode(hasBorder, forKey: .hasBorder)
        try container.encode(isInset, forKey: .isInset)
        try container.encode(IceColor(cgColor: borderColor), forKey: .borderColor)
        try container.encode(borderWidth, forKey: .borderWidth)
        try container.encode(shapeKind, forKey: .shapeKind)
        try container.encode(fullShapeInfo, forKey: .fullShapeInfo)
        try container.encode(splitShapeInfo, forKey: .splitShapeInfo)
        try container.encode(tintKind, forKey: .tintKind)
        try container.encode(IceColor(cgColor: tintColor), forKey: .tintColor)
        try container.encode(tintGradient, forKey: .tintGradient)
    }
}
