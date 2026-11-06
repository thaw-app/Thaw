//
//  GlassCornerRadiusTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@MainActor
@Suite("Glass under a shape reaches the shape's corners")
struct GlassCornerRadiusTests {
    @Test("A menu bar shape gets a capsule of glass")
    func capsuleByDefault() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 24)
        #expect(MenuBarLiquidGlassGeometry.glassCornerRadius(for: bounds) == 12)
    }

    @Test("A Thaw Bar with square corners keeps its quarter-height corners")
    func squareCornersKeepTheirRadius() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 24)
        let clip = ThawBarBorderShape.thawBarClip(height: 24, hasRoundedShape: false)
        #expect(MenuBarLiquidGlassGeometry.glassCornerRadius(for: bounds, pathCornerRadius: clip.cornerRadius) == 6)
    }

    @Test("A bar several rows tall keeps one row's rounding")
    func tallBarKeepsRowRounding() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 96)
        let clip = ThawBarBorderShape.thawBarClip(height: 24, hasRoundedShape: true)
        #expect(MenuBarLiquidGlassGeometry.glassCornerRadius(for: bounds, pathCornerRadius: clip.cornerRadius) == 12)
    }

    @Test("A radius the bounds cannot hold falls back to the capsule")
    func oversizedRadiusIsCapped() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 24)
        #expect(MenuBarLiquidGlassGeometry.glassCornerRadius(for: bounds, pathCornerRadius: 40) == 12)
        #expect(MenuBarLiquidGlassGeometry.glassCornerRadius(for: bounds, pathCornerRadius: -3) == 0)
    }
}
