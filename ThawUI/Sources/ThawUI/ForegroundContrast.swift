//
//  ForegroundContrast.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Picks black or white content for a measured background by WCAG relative luminance. Perceived-brightness
/// weights (0.299 / 0.587 / 0.114) disagree on saturated colors: pure green gets white at 1.37:1, not black at 15.30:1.
///
/// The contrast curves cross at luminance ≈ 0.1791, at 4.58:1, so the chosen color never drops below
/// that, above the 4.5:1 AA floor for normal text, on any opaque sRGB background.
public nonisolated enum ForegroundContrast {
    /// The relative luminance at which black overtakes white: where white's 1.05 / (L + 0.05)
    /// equals black's (L + 0.05) / 0.05.
    public static let flipLuminance = (0.05 * 1.05).squareRoot() - 0.05

    /// Whether black wins on a background of known relative luminance, such as a SwiftUI Color
    /// resolved to linear components.
    public static func prefersDarkContent(onLuminance luminance: Double) -> Bool {
        luminance > flipLuminance
    }

    /// WCAG contrast ratio between two relative luminances in either order, from 1 to 21.
    public static func contrastRatio(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// WCAG relative luminance of color, from 0 to 1, or nil when it cannot be expressed in sRGB.
    public static func relativeLuminance(of color: CGColor) -> Double? {
        guard let components = sRGBComponents(of: color) else {
            return nil
        }
        return relativeLuminance(
            linearRed: linearized(components.red),
            linearGreen: linearized(components.green),
            linearBlue: linearized(components.blue)
        )
    }

    /// WCAG relative luminance of one already-linearized RGB triple.
    public static func relativeLuminance(linearRed: Double, linearGreen: Double, linearBlue: Double) -> Double {
        (0.2126 * linearRed) + (0.7152 * linearGreen) + (0.0722 * linearBlue)
    }

    /// overlay painted over base at opacity, as one opaque color, or nil when either has no sRGB form.
    /// Content under a wash is drawn on this result, so judge the flip against it wherever a tint covers the surface.
    ///
    /// The overlay's own alpha is honored; the base is treated as opaque.
    public static func composited(_ overlay: CGColor, over base: CGColor, opacity: Double) -> CGColor? {
        guard
            let overlay = sRGBComponents(of: overlay),
            let base = sRGBComponents(of: base)
        else {
            return nil
        }
        // Blended on the encoded channels, where SwiftUI and AppKit blend a translucent fill;
        // linearizing first lands on a different color than the one on screen.
        let alpha = min(max(opacity, 0), 1) * overlay.alpha
        let mix = { (over: Double, under: Double) in (over * alpha) + (under * (1 - alpha)) }
        return CGColor(
            srgbRed: mix(overlay.red, base.red),
            green: mix(overlay.green, base.green),
            blue: mix(overlay.blue, base.blue),
            alpha: 1
        )
    }

    /// Removes the sRGB transfer function from one channel.
    static func linearized(_ channel: Double) -> Double {
        let channel = min(max(channel, 0), 1)
        return channel <= 0.04045
            ? channel / 12.92
            : pow((channel + 0.055) / 1.055, 2.4)
    }

    /// color expressed in sRGB, or nil when it has no such expression. Wide-gamut colors clamp, which only
    /// pulls a channel toward the middle, so it cannot turn a background needing one polarity into the other.
    public static func sRGBComponents(
        of color: CGColor
    ) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        guard
            let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
            let converted = color.converted(to: sRGB, intent: .defaultIntent, options: nil),
            let components = converted.components,
            components.count >= 3
        else {
            return nil
        }
        return (
            Double(components[0]),
            Double(components[1]),
            Double(components[2]),
            components.count >= 4 ? Double(components[3]) : 1
        )
    }
}
