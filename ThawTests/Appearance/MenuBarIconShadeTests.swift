//
//  MenuBarIconShadeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

struct MenuBarIconShadeTests {
    /// count opaque pixels of one grey level, padded with transparent ones.
    private func pixels(grey: UInt8, count: Int, transparent: Int = 100) -> [UInt8] {
        Array(repeating: [grey, grey, grey, 255], count: count).flatMap(\.self)
            + Array(repeating: [0, 0, 0, 0], count: transparent).flatMap(\.self)
    }

    @Test
    func `white glyphs read light and black glyphs read dark`() {
        #expect(MenuBarIconShade.shade(ofPremultipliedRGBA: pixels(grey: 240, count: 60)) == .light)
        #expect(MenuBarIconShade.shade(ofPremultipliedRGBA: pixels(grey: 20, count: 60)) == .dark)
    }

    @Test
    func `too few glyph pixels say nothing`() {
        #expect(MenuBarIconShade.shade(ofPremultipliedRGBA: pixels(grey: 240, count: 10)) == nil)
        #expect(MenuBarIconShade.shade(ofPremultipliedRGBA: []) == nil)
    }

    @Test
    func `faint edge pixels don't count, only mostly opaque ones`() {
        let faint = Array(repeating: [10, 10, 10, 60] as [UInt8], count: 500).flatMap(\.self)
        #expect(MenuBarIconShade.shade(ofPremultipliedRGBA: faint + pixels(grey: 240, count: 60)) == .light)
    }

    @Test
    func `the glass goes light under dark icons and dark under light ones`() {
        #expect(MenuBarIconShade.dark.matchingGlassAppearance == .aqua)
        #expect(MenuBarIconShade.light.matchingGlassAppearance == .darkAqua)
    }

    @Test
    func `a real image is read through the same decision`() throws {
        let context = try #require(CGContext(
            data: nil, width: 40, height: 10, bitsPerComponent: 8, bytesPerRow: 160,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        let image = try #require(context.makeImage())
        #expect(MenuBarIconShade.shade(of: image) == .light)
    }
}
