//
//  ForegroundContrast.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Picks black or white content for a measured background, in the color space
/// the contrast requirement is written in.
///
/// WCAG states its 4.5:1 (text) and 3:1 (controls and glyphs) floors in terms
/// of relative luminance: channels linearized out of sRGB, then weighted
/// 0.2126 / 0.7152 / 0.0722. Perceived-brightness weighting (0.299 / 0.587 /
/// 0.114 on gamma-encoded channels) is a different quantity and disagrees
/// outright on saturated colors: pure green reads 0.587 there, which asks for
/// white text at 1.37:1, against a relative luminance of 0.715, which asks
/// for black at 15.30:1.
///
/// - Note: Choosing whichever of black and white wins has a floor. The two
///   contrast curves cross at relative luminance sqrt(0.05 × 1.05) − 0.05
///   ≈ 0.1791, where both measure 4.58:1, and every other background gives
///   one of them more. So the chosen one never drops below 4.58:1, above the
///   4.5:1 AA floor for normal text, on any opaque sRGB background.
nonisolated enum ForegroundContrast {
    /// The relative luminance at which black overtakes white.
    ///
    /// Below it white contrasts more with the background, above it black does.
    /// Derived rather than tuned: white against a background of luminance L
    /// measures 1.05 / (L + 0.05) and black measures (L + 0.05) / 0.05,
    /// and the two are equal at sqrt(0.05 × 1.05) − 0.05.
    static let flipLuminance = (0.05 * 1.05).squareRoot() - 0.05

    /// The same judgement for a background whose relative luminance is already
    /// known, a SwiftUI Color resolved to linear components, say.
    ///
    /// - Parameter luminance: WCAG relative luminance of the background.
    /// - Returns: true when black wins.
    static func prefersDarkContent(onLuminance luminance: Double) -> Bool {
        luminance > flipLuminance
    }

    /// WCAG relative luminance of color, from 0 to 1, or nil when it
    /// cannot be expressed in sRGB.
    ///
    /// - Parameter color: The color to measure.
    static func relativeLuminance(of color: CGColor) -> Double? {
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
    ///
    /// - Parameters:
    ///   - linearRed: Red channel, gamma removed.
    ///   - linearGreen: Green channel, gamma removed.
    ///   - linearBlue: Blue channel, gamma removed.
    static func relativeLuminance(linearRed: Double, linearGreen: Double, linearBlue: Double) -> Double {
        (0.2126 * linearRed) + (0.7152 * linearGreen) + (0.0722 * linearBlue)
    }

    /// overlay painted over base at opacity, as one opaque color.
    ///
    /// Content drawn under a wash is drawn on the result, not on base, so
    /// this is the color the flip above has to be judged against wherever a
    /// tint covers the same surface.
    ///
    /// - Parameters:
    ///   - overlay: The color painted on top. Its own alpha is honored.
    ///   - base: The color underneath. Treated as opaque.
    ///   - opacity: Opacity the overlay is painted at, from 0 to 1.
    /// - Returns: The composited color, or nil when either color cannot be
    ///   expressed in sRGB.
    static func composited(_ overlay: CGColor, over base: CGColor, opacity: Double) -> CGColor? {
        guard
            let overlay = sRGBComponents(of: overlay),
            let base = sRGBComponents(of: base)
        else {
            return nil
        }
        // Blended on the encoded channels, which is where SwiftUI and
        // AppKit blend a translucent fill; linearizing first would land on a
        // different color than the one actually on screen.
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
    ///
    /// - Parameter channel: Encoded channel value, from 0 to 1.
    private static func linearized(_ channel: Double) -> Double {
        let channel = min(max(channel, 0), 1)
        return channel <= 0.04045
            ? channel / 12.92
            : pow((channel + 0.055) / 1.055, 2.4)
    }

    /// color expressed in sRGB, or nil when it has no such expression.
    ///
    /// Wide-gamut colors clamp into the sRGB volume here. The clamp only ever
    /// pulls a channel toward the middle, so it cannot turn a background that
    /// needs one polarity into one that needs the other.
    ///
    /// - Parameter color: The color to convert.
    static func sRGBComponents(
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
