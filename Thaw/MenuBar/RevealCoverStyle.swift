//
//  RevealCoverStyle.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// How RevealCover paints Thaw's menu bar look over the wallpaper.
///
/// The overlay's glass captures as flat grey, so the cover draws the wallpaper
/// strip, blurred for glass, under flat washes of the configured fills.
@MainActor
enum RevealCoverStyle {
    /// One flat color laid over the wallpaper.
    struct Wash: Equatable {
        let color: CGColor
        let opacity: Double
    }

    struct Style: Equatable {
        /// Laid over the wallpaper in order.
        var washes: [Wash] = []
        /// Whether the wallpaper under the band is frosted, as glass frosts it.
        var blursWallpaper = false
    }

    /// Average alpha of the dark fade the dynamic glass draws.
    static let darkFadeOpacity = 0.5638

    /// The look over the cover's band, left of the visible items.
    ///
    /// The shape fill applies only with no shape or a Full shape; Split and
    /// Notch draw their trailing part around the visible items, not the band.
    static func style(
        for configuration: MenuBarAppearancePartialConfiguration,
        shapeKind: MenuBarShapeKind,
        adaptiveColor: CGColor?
    ) -> Style {
        var style = Style()
        add(
            Layer(
                kind: fill(configuration.backgroundKind),
                color: configuration.backgroundColor,
                gradientAverage: configuration.backgroundGradient.averageColor(),
                opacity: configuration.backgroundOpacity,
                glassStyle: configuration.backgroundGlassStyle,
                glassIsColored: configuration.backgroundGlassIsColored
            ),
            adaptiveColor: adaptiveColor,
            to: &style
        )
        if shapeKind == .noShape || shapeKind == .full {
            add(
                Layer(
                    kind: fill(configuration.tintKind),
                    color: configuration.tintColor,
                    gradientAverage: configuration.tintGradient.averageColor(),
                    opacity: configuration.tintOpacity,
                    glassStyle: configuration.tintGlassStyle,
                    glassIsColored: configuration.tintGlassIsColored
                ),
                adaptiveColor: adaptiveColor,
                to: &style
            )
        }
        return style
    }

    private enum Fill {
        case none, solid, gradient, glass, adaptive
    }

    /// One of the two fills the band repeats: the shape's background or its tint.
    private struct Layer {
        let kind: Fill
        let color: CGColor
        let gradientAverage: CGColor?
        let opacity: Double
        let glassStyle: MenuBarGlassStyle
        let glassIsColored: Bool
    }

    private static func fill(_ kind: MenuBarBackgroundKind) -> Fill {
        switch kind {
        case .none: .none
        case .solid: .solid
        case .gradient: .gradient
        case .glass: .glass
        case .adaptive: .adaptive
        }
    }

    private static func fill(_ kind: MenuBarTintKind) -> Fill {
        switch kind {
        case .noTint: .none
        case .solid: .solid
        case .gradient: .gradient
        case .glass: .glass
        case .adaptive, .adaptiveGradient: .adaptive
        }
    }

    private static func add(_ layer: Layer, adaptiveColor: CGColor?, to style: inout Style) {
        let opacity = layer.opacity
        switch layer.kind {
        case .none:
            break
        case .solid:
            style.washes.append(Wash(color: layer.color, opacity: opacity))
        case .gradient:
            if let gradientAverage = layer.gradientAverage {
                style.washes.append(Wash(color: gradientAverage, opacity: opacity))
            }
        case .adaptive:
            if let adaptiveColor {
                style.washes.append(Wash(color: adaptiveColor, opacity: opacity))
            }
        case .glass:
            style.blursWallpaper = true
            if layer.glassStyle.usesTint, layer.glassIsColored {
                style.washes.append(Wash(color: layer.color, opacity: opacity * layer.glassStyle.effectOpacity))
            }
            if layer.glassStyle.usesDarkFade {
                style.washes.append(Wash(color: CGColor(gray: 0, alpha: 1), opacity: darkFadeOpacity))
            }
        }
    }
}
