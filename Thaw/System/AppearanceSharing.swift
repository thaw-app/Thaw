//
//  AppearanceSharing.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// The menu bar appearance as partner apps receive it: the resolved look for the
/// current color scheme, not Thaw's settings model. Additive changes keep version.
nonisolated struct SharedAppearance: Encodable, Equatable {
    static let currentVersion = 1

    /// Posted to the distributed center when the shared appearance changes. It carries
    /// no payload; a receiver fetches the appearance again with thaw://get-appearance.
    static let didChangeNotification = Notification.Name("com.stonerl.Thaw.appearanceDidChange")

    /// Components in sRGB, each from 0 to 1.
    struct Color: Encodable, Equatable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        /// nil when the color has no sRGB form, such as a pattern color.
        init?(_ color: CGColor) {
            guard let components = ForegroundContrast.sRGBComponents(of: color) else { return nil }
            self.red = components.red
            self.green = components.green
            self.blue = components.blue
            self.alpha = components.alpha
        }
    }

    struct GradientStop: Encodable, Equatable {
        let color: Color
        /// From 0 at the leading edge to 1 at the trailing edge.
        let location: Double
    }

    /// One fill layer. color is set for solid, stops for gradient, and
    /// glassStyle and glassIsColored for glass.
    struct Fill: Encodable, Equatable {
        let kind: String
        let opacity: Double
        let color: Color?
        let stops: [GradientStop]?
        let glassStyle: String?
        let glassIsColored: Bool?
    }

    struct Border: Encodable, Equatable {
        let color: Color?
        let width: Double
        let style: String
    }

    let version: Int
    /// "light" or "dark": the scheme these values were resolved for.
    let colorScheme: String
    /// "none", "full", "split" or "notch".
    let shape: String
    let hasRoundedShape: Bool
    let hasShadow: Bool
    /// nil when the border is off.
    let border: Border?
    let tint: Fill
    let background: Fill
}

nonisolated extension SharedAppearance {
    init(
        configuration: MenuBarAppearancePartialConfiguration,
        shapeKind: MenuBarShapeKind,
        hasRoundedShape: Bool,
        isDark: Bool
    ) {
        self.version = Self.currentVersion
        self.colorScheme = isDark ? "dark" : "light"
        self.shape = Self.name(of: shapeKind)
        self.hasRoundedShape = hasRoundedShape
        self.hasShadow = configuration.hasShadow
        self.border = configuration.hasBorder
            ? Border(
                color: Color(configuration.borderColor),
                width: configuration.borderWidth,
                style: Self.name(of: configuration.borderStyle)
            )
            : nil
        self.tint = Self.fill(
            kind: Self.name(of: configuration.tintKind),
            opacity: configuration.tintOpacity,
            color: configuration.tintColor,
            gradient: configuration.tintGradient,
            glassStyle: configuration.tintGlassStyle,
            glassIsColored: configuration.tintGlassIsColored
        )
        self.background = Self.fill(
            kind: Self.name(of: configuration.backgroundKind),
            opacity: configuration.backgroundOpacity,
            color: configuration.backgroundColor,
            gradient: configuration.backgroundGradient,
            glassStyle: configuration.backgroundGlassStyle,
            glassIsColored: configuration.backgroundGlassIsColored
        )
    }

    private static func fill(
        kind: String,
        opacity: Double,
        color: CGColor,
        gradient: ThawGradient,
        glassStyle: MenuBarGlassStyle,
        glassIsColored: Bool
    ) -> Fill {
        let isGlass = kind == "glass"
        // A colored glass still needs its color, so glass keeps it too.
        let carriesColor = kind == "solid" || (isGlass && glassIsColored)
        return Fill(
            kind: kind,
            opacity: opacity,
            color: carriesColor ? Color(color) : nil,
            stops: kind == "gradient"
                ? gradient.stops.compactMap { stop in
                    Color(stop.color).map { GradientStop(color: $0, location: Double(stop.location)) }
                }
                : nil,
            glassStyle: isGlass ? name(of: glassStyle) : nil,
            glassIsColored: isGlass ? glassIsColored : nil
        )
    }

    private static func name(of kind: MenuBarShapeKind) -> String {
        switch kind {
        case .noShape: "none"
        case .full: "full"
        case .split: "split"
        case .notch: "notch"
        }
    }

    private static func name(of kind: MenuBarTintKind) -> String {
        switch kind {
        case .noTint: "none"
        case .solid: "solid"
        case .gradient: "gradient"
        case .glass: "glass"
        case .adaptive: "adaptive"
        case .adaptiveGradient: "adaptiveGradient"
        }
    }

    private static func name(of kind: MenuBarBackgroundKind) -> String {
        switch kind {
        case .none: "none"
        case .solid: "solid"
        case .gradient: "gradient"
        case .glass: "glass"
        case .adaptive: "adaptive"
        }
    }

    private static func name(of style: MenuBarGlassStyle) -> String {
        switch style {
        case .regular: "regular"
        case .clear: "clear"
        case .liquid: "liquid"
        case .dynamic: "dynamic"
        }
    }

    private static func name(of style: MenuBarBorderStyle) -> String {
        switch style {
        case .solid: "solid"
        case .dashed: "dashed"
        case .dotted: "dotted"
        }
    }
}
