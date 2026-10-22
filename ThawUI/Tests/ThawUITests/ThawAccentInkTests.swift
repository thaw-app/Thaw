//
//  ThawAccentInkTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import ThawUI

@Suite("Accent ink")
struct ThawAccentInkTests {
    /// Thaw's gold, light and dark, and its Increase Contrast variants, as the
    /// asset catalog defines them (Display P3, read here as sRGB).
    private static let golds: [ThawAccentInk.RGB] = [
        .init(red: 1, green: 0.76, blue: 0.2),
        .init(red: 0.9, green: 0.684, blue: 0.18),
        .init(red: 1, green: 0.856, blue: 0.52),
    ]

    private static func contrast(_ first: ThawAccentInk.RGB, _ second: ThawAccentInk.RGB) -> Double {
        ForegroundContrast.contrastRatio(first.luminance, second.luminance)
    }

    @Test("gold gets a dark shade of itself that clears 7:1", arguments: golds)
    func goldGetsShade(gold: ThawAccentInk.RGB) {
        let ink = ThawAccentInk.ink(on: gold, increasedContrast: false)
        #expect(ink != .white)
        #expect(ink != .black)
        #expect(Self.contrast(gold, ink) >= ThawAccentInk.shadeContrastFloor)
        // A shade keeps the fill's warmth: red stays ahead of blue.
        #expect(ink.red > ink.blue)
    }

    @Test("Increase Contrast draws pure black on gold", arguments: golds)
    func increasedContrastIsBlack(gold: ThawAccentInk.RGB) {
        #expect(ThawAccentInk.ink(on: gold, increasedContrast: true) == .black)
    }

    @Test("white would fail on gold, which is why the label is dark", arguments: golds)
    func whiteFailsOnGold(gold: ThawAccentInk.RGB) {
        #expect(Self.contrast(gold, .white) < 3)
    }

    @Test("a dark fill gets white", arguments: [false, true])
    func darkFillGetsWhite(increasedContrast: Bool) {
        let navy = ThawAccentInk.RGB(red: 0, green: 0.2, blue: 0.6)
        #expect(ThawAccentInk.ink(on: navy, increasedContrast: increasedContrast) == .white)
    }

    @Test("a fill just past the flip falls back to black")
    func fillNearFlipFallsBackToBlack() {
        // Grey whose luminance sits just above ForegroundContrast.flipLuminance:
        // black measures under 5:1 there, so no shade reaches 7:1.
        let grey = ThawAccentInk.RGB(red: 0.47, green: 0.47, blue: 0.47)
        #expect(ForegroundContrast.prefersDarkContent(onLuminance: grey.luminance))
        #expect(ThawAccentInk.ink(on: grey, increasedContrast: false) == .black)
    }

    @Test("channels clamp into range")
    func channelsClamp() {
        let wide = ThawAccentInk.RGB(red: 1.08, green: 0.74, blue: -0.1)
        #expect(wide == ThawAccentInk.RGB(red: 1, green: 0.74, blue: 0))
    }

    @Test("contrast ratio is symmetric and spans 1 to 21")
    func contrastRatioBounds() {
        #expect(ForegroundContrast.contrastRatio(1, 0) == 21)
        #expect(ForegroundContrast.contrastRatio(0, 1) == 21)
        #expect(ForegroundContrast.contrastRatio(0.4, 0.4) == 1)
    }
}
