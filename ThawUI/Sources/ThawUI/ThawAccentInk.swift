//
//  ThawAccentInk.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Label colour on a solid accent fill: white on a dark fill, black under Increase Contrast,
/// otherwise the lightest shade of the fill that reaches 7:1.
public nonisolated enum ThawAccentInk {
    /// An sRGB colour with gamma-encoded channels from 0 to 1.
    public struct RGB: Equatable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = min(max(red, 0), 1)
            self.green = min(max(green, 0), 1)
            self.blue = min(max(blue, 0), 1)
        }

        public static let black = RGB(red: 0, green: 0, blue: 0)
        public static let white = RGB(red: 1, green: 1, blue: 1)

        /// WCAG relative luminance.
        public var luminance: Double {
            ForegroundContrast.relativeLuminance(
                linearRed: ForegroundContrast.linearized(red),
                linearGreen: ForegroundContrast.linearized(green),
                linearBlue: ForegroundContrast.linearized(blue)
            )
        }

        /// The colour with every channel scaled toward black by factor.
        func shaded(by factor: Double) -> RGB {
            RGB(red: red * factor, green: green * factor, blue: blue * factor)
        }
    }

    /// The contrast a shaded dark label has to reach, the WCAG AAA text floor.
    public static let shadeContrastFloor = 7.0

    /// The label colour on fill, an opaque colour.
    public static func ink(on fill: RGB, increasedContrast: Bool) -> RGB {
        let fillLuminance = fill.luminance
        guard ForegroundContrast.prefersDarkContent(onLuminance: fillLuminance) else {
            return .white
        }
        guard !increasedContrast else {
            return .black
        }
        // Thirty percent of the fill first, then darker in steps of five.
        for step in stride(from: 6, through: 1, by: -1) {
            let shade = fill.shaded(by: Double(step) * 0.05)
            if ForegroundContrast.contrastRatio(fillLuminance, shade.luminance) >= shadeContrastFloor {
                return shade
            }
        }
        return .black
    }

    /// The label colour on tint, resolved for the environment's appearance and contrast setting.
    public static func color(on tint: Color, in environment: EnvironmentValues) -> Color {
        let resolved = tint.resolve(in: environment)
        let fill = RGB(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
        let ink = ink(on: fill, increasedContrast: environment.colorSchemeContrast == .increased)
        return Color(.sRGB, red: ink.red, green: ink.green, blue: ink.blue)
    }
}
