//
//  ThawBarAppearanceForeground.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

@MainActor
enum ThawBarAppearanceForeground {
    static func resolve(
        appearance: ResolvedThawBarAppearance,
        sampledInfo: MenuBarAverageColorInfo?,
        adaptiveInfo: MenuBarAverageColorInfo?,
        palette: WallpaperPalette?,
        screen: NSScreen?
    ) -> Color {
        var result = sampledInfo ?? MenuBarAverageColorInfo(
            color: NSColor(Color.defaultLayoutBar).cgColor,
            source: .menuBarWindow
        )
        let adaptive = adaptiveInfo?.color ?? result.color
        switch appearance.backgroundKind {
        case .none:
            break
        case .solid:
            result = result.tinted(by: appearance.backgroundColor, opacity: appearance.backgroundOpacity)
        case .gradient:
            if let color = appearance.backgroundGradient.averageColor() {
                result = result.tinted(by: color, opacity: appearance.backgroundOpacity)
            }
        case .adaptive:
            result = result.tinted(by: adaptive, opacity: appearance.backgroundOpacity)
        case .glass:
            result = glassSample(
                result,
                style: appearance.backgroundGlassStyle,
                colored: appearance.backgroundGlassIsColored,
                color: appearance.backgroundColor,
                opacity: appearance.backgroundOpacity
            )
        }

        switch appearance.tintKind {
        case .noTint:
            break
        case .solid:
            result = result.tinted(by: appearance.tintColor, opacity: appearance.tintOpacity)
        case .gradient:
            if let color = appearance.tintGradient.averageColor() {
                result = result.tinted(by: color, opacity: appearance.tintOpacity)
            }
        case .adaptive:
            result = result.tinted(by: adaptive, opacity: appearance.tintOpacity)
        case .adaptiveGradient:
            let color = paletteAverage(palette) ?? adaptive
            result = result.tinted(by: color, opacity: appearance.tintOpacity)
        case .glass:
            result = glassSample(
                result,
                style: appearance.tintGlassStyle,
                colored: appearance.tintGlassIsColored,
                color: appearance.tintColor,
                opacity: appearance.tintOpacity
            )
        }
        return result.isBright(for: screen) ? .black : .white
    }

    private static func paletteAverage(_ palette: WallpaperPalette?) -> CGColor? {
        guard let primary = palette?.primary, let secondary = palette?.secondary,
              let space = CGColorSpace(name: CGColorSpace.displayP3)
        else { return nil }
        return CGColor(colorSpace: space, components: [
            CGFloat((primary.red + secondary.red) / 2),
            CGFloat((primary.green + secondary.green) / 2),
            CGFloat((primary.blue + secondary.blue) / 2),
            1,
        ])
    }

    private static func glassSample(
        _ sample: MenuBarAverageColorInfo,
        style: MenuBarGlassStyle,
        colored: Bool,
        color: CGColor,
        opacity: Double
    ) -> MenuBarAverageColorInfo {
        var result = sample
        if style.usesTint, colored {
            result = result.tinted(by: color, opacity: opacity * style.effectOpacity)
        }
        if style.usesDarkFade {
            // Average alpha of the four stops in MenuBarLiquidGlassFadeView.
            result = result.tinted(by: NSColor.black.cgColor, opacity: 0.5638)
        }
        return result
    }
}
