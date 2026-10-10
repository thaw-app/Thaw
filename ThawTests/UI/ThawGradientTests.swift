//
//  ThawGradientTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import Testing
@testable import Thaw

/// Covers the stored form of ThawGradient and the way its angle reaches the
/// pixels.
///
/// The angle arrived after gradients were already on disk, so a gradient
/// without the key must still decode, and decode as the left-to-right fill
/// it always painted. Floe mirrors the angle, so its meaning is pinned too.
@MainActor
@Suite("Thaw gradient")
struct ThawGradientTests {
    private static let redToBlue = ThawGradient(stops: [
        .stop(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), location: 0),
        .stop(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), location: 1),
    ])

    // MARK: - Stored Format

    @Test("A gradient saved before the angle existed decodes as horizontal")
    func legacyGradientDecodesAsHorizontal() throws {
        let encoded = try JSONEncoder().encode(Self.redToBlue)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object.removeValue(forKey: "angle") != nil)
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ThawGradient.self, from: legacy)
        #expect(decoded.angle == 90)
        #expect(decoded.stops.count == 2)
    }

    @Test("The angle survives an encoding round trip")
    func angleRoundTrips() throws {
        var gradient = Self.redToBlue
        gradient.angle = 135

        let decoded = try JSONDecoder().decode(ThawGradient.self, from: JSONEncoder().encode(gradient))
        #expect(decoded.angle == 135)
    }

    @Test("Changing the alpha keeps the angle")
    func withAlphaKeepsAngle() {
        var gradient = Self.redToBlue
        gradient.angle = 135
        #expect(gradient.withAlpha(0.5).angle == 135)
    }

    // MARK: - Drawing

    /// Where the first stop lands for each quarter turn. Bitmap rows count
    /// down from the top.
    @Test("The first stop sits where the angle starts", arguments: [
        (angle: 0.0, start: (x: 10, y: 1), end: (x: 10, y: 18)),
        (angle: 90.0, start: (x: 1, y: 10), end: (x: 18, y: 10)),
        (angle: 180.0, start: (x: 10, y: 18), end: (x: 10, y: 1)),
        (angle: 270.0, start: (x: 18, y: 10), end: (x: 1, y: 10)),
        (angle: 360.0, start: (x: 10, y: 1), end: (x: 10, y: 18)),
    ])
    func firstStopSitsWhereTheAngleStarts(
        angle: Double,
        start: (x: Int, y: Int),
        end: (x: Int, y: Int)
    ) throws {
        var gradient = Self.redToBlue
        gradient.angle = angle

        let bitmap = try render(gradient)
        let first = try #require(bitmap.colorAt(x: start.x, y: start.y))
        let last = try #require(bitmap.colorAt(x: end.x, y: end.y))
        #expect(first.redComponent > first.blueComponent)
        #expect(last.blueComponent > last.redComponent)
    }

    @Test("A diagonal starts in the corner it points away from")
    func diagonalStartsInItsCorner() throws {
        var gradient = Self.redToBlue
        gradient.angle = 45

        // Halfway between top to bottom and leading to trailing.
        let bitmap = try render(gradient)
        let topLeading = try #require(bitmap.colorAt(x: 1, y: 1))
        let bottomTrailing = try #require(bitmap.colorAt(x: 18, y: 18))
        #expect(topLeading.redComponent > topLeading.blueComponent)
        #expect(bottomTrailing.blueComponent > bottomTrailing.redComponent)
    }

    private func render(_ gradient: ThawGradient) throws -> NSBitmapImageRep {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 20,
            pixelsHigh: 20,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        gradient.draw(in: CGRect(x: 0, y: 0, width: 20, height: 20), using: .sRGB)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}
