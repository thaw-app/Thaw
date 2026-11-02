//
//  MenuBarBackdropTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@MainActor
@Suite("Menu bar backdrop")
struct MenuBarBackdropTests {
    private func image() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try #require(context.makeImage())
    }

    @Test("A band maps to its slice of the strip, on a display left of the main one too")
    func contentsRect() throws {
        let strip = try MenuBarBackdrop.Strip(rect: CGRect(x: -200, y: 10, width: 200, height: 35), image: image())
        let unit = strip.contentsRect(for: CGRect(x: -150, y: 10, width: 100, height: 35))
        #expect(unit == CGRect(x: 0.25, y: 0, width: 0.5, height: 1))
    }

    @Test("Only on-screen windows below the ceiling that touch the rect are composited")
    func windowsBelowTheBar() async {
        let everywhere = CGRect(x: -100_000, y: -100_000, width: 200_000, height: 200_000)
        let below = await MenuBarBackdrop.windowsBelowMenuBar(intersecting: everywhere)
        #expect(below.allSatisfy { $0.bounds.intersects(everywhere) })
        #expect(Set(below.map(\.id)).count == below.count)
        #expect(await MenuBarBackdrop.windowsBelowMenuBar(intersecting: everywhere, belowLayer: Int.min).isEmpty)
        #expect(await MenuBarBackdrop.windowsBelowMenuBar(intersecting: CGRect(x: -900_000, y: -900_000, width: 1, height: 1)).isEmpty)
    }

    @Test("A one-off read under no window composites nothing")
    @MainActor
    func captureNothing() async {
        let image = await MenuBarBackdrop().capture(CGRect(x: 0, y: 0, width: 10, height: 10), belowLayer: Int.min)
        #expect(image == nil)
    }
}
