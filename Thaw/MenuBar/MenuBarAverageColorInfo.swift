//
//  MenuBarAverageColorInfo.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import ThawUI

/// A color sample and its source, kept as a Hashable value so equality determines whether repainting is needed.
struct MenuBarAverageColorInfo: Hashable {
    /// Where a sample was measured. The menu bar window itself is preferred;
    /// the desktop picture stands in when that window cannot be read.
    enum Source: Hashable {
        case menuBarWindow
        case desktopWallpaper
    }

    var color: CGColor

    var source: Source

    /// WCAG relative luminance (0...1) for contrast floors; returns 0 if the color cannot convert to sRGB.
    var relativeLuminance: Double {
        ForegroundContrast.relativeLuminance(of: color) ?? 0
    }

    /// A separate notch threshold allows darker foreground beside the notch, where content reads lighter.
    /// Both thresholds use the contrast crossover to avoid weakening either polarity.
    /// - Parameter screen: Screen to judge for; nil uses the screen currently owning the menu bar.
    /// - Returns: true if the background calls for dark foreground content.
    func isBright(for screen: NSScreen?) -> Bool {
        let subject = screen ?? NSScreen.screenWithActiveMenuBar
        let threshold = subject?.hasNotch == true
            ? Constants.notchedDisplayBrightnessThreshold
            : Constants.menuBarBrightnessThreshold
        return relativeLuminance > threshold
    }

    /// Judge the tinted background, not the raw sample: even 20% black over #808080 changes the preferred polarity.
    /// - Parameters:
    ///   - tint: The tint color painted over the sample.
    ///   - opacity: Opacity the tint is painted at, from 0 to 1.
    /// - Returns: The composited sample, or self if tint cannot convert to sRGB.
    func tinted(by tint: CGColor, opacity: Double) -> MenuBarAverageColorInfo {
        guard let composited = ForegroundContrast.composited(tint, over: color, opacity: opacity) else {
            return self
        }
        return MenuBarAverageColorInfo(color: composited, source: source)
    }
}
