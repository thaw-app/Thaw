//
//  MenuBarAppearanceConfigurationV2.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct MenuBarAppearanceConfigurationV2: Hashable {
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
}

// MARK: Default Configuration

extension MenuBarAppearanceConfigurationV2 {
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
        isDynamic: false
    )
}

extension MenuBarAppearanceConfigurationV2: Codable {
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
            isDynamic: container.decodeIfPresent(Bool.self, forKey: .isDynamic) ?? Self.defaultConfiguration.isDynamic
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
    }
}

// MARK: - MenuBarAppearancePartialConfiguration

struct MenuBarAppearancePartialConfiguration: Hashable {
    var hasShadow: Bool
    var hasBorder: Bool
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
}

// MARK: Default Partial Configuration

extension MenuBarAppearancePartialConfiguration {
    static let defaultConfiguration = MenuBarAppearancePartialConfiguration(
        hasShadow: false,
        hasBorder: false,
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
        tintGlassStyle: .regular
    )
}

// MARK: MenuBarAppearancePartialConfiguration: Codable

extension MenuBarAppearancePartialConfiguration: Codable {
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            hasShadow: container.decodeIfPresent(Bool.self, forKey: .hasShadow) ?? Self.defaultConfiguration.hasShadow,
            hasBorder: container.decodeIfPresent(Bool.self, forKey: .hasBorder) ?? Self.defaultConfiguration.hasBorder,
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
