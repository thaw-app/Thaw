//
//  ThawColorCodingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import ThawUI

/// Colors come from saved settings and imported profiles, so the component count must match the color space.
@Suite("Color coding")
struct ThawColorCodingTests {
    private struct Payload: Encodable {
        let components: [CGFloat]
        let colorSpace: Data
    }

    private static func srgbData() throws -> Data {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        return try #require(space.copyICCData()) as Data
    }

    private static func decode(components: [CGFloat]) throws -> ThawColor {
        let data = try JSONEncoder().encode(Payload(components: components, colorSpace: srgbData()))
        return try JSONDecoder().decode(ThawColor.self, from: data)
    }

    @Test("Too few components are refused")
    func tooFewComponentsAreRefused() {
        #expect(throws: DecodingError.self) {
            try Self.decode(components: [0.5])
        }
    }

    @Test("No components are refused")
    func emptyComponentsAreRefused() {
        #expect(throws: DecodingError.self) {
            try Self.decode(components: [])
        }
    }

    @Test("Too many components are refused")
    func tooManyComponentsAreRefused() {
        #expect(throws: DecodingError.self) {
            try Self.decode(components: [0.1, 0.2, 0.3, 1, 0.5])
        }
    }

    @Test("A color round-trips through encoding")
    func roundTrips() throws {
        let color = try Self.decode(components: [0.1, 0.2, 0.3, 1])
        let data = try JSONEncoder().encode(color)
        let decoded = try JSONDecoder().decode(ThawColor.self, from: data)
        #expect(decoded.cgColor.components == color.cgColor.components)
    }
}
