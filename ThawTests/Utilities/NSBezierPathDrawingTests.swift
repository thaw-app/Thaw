//
//  NSBezierPathDrawingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@MainActor
@Suite("Bezier path drawing")
struct NSBezierPathDrawingTests {
    private static let size = 40

    /// Runs body with a fresh transparent RGBA bitmap as the current graphics context and returns its pixels.
    private func render(_ body: () -> Void) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: Self.size * Self.size * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: Self.size, height: Self.size, bitsPerComponent: 8,
                bytesPerRow: Self.size * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            body()
            NSGraphicsContext.restoreGraphicsState()
        }
        return pixels
    }

    /// The alpha at x, y in a bitmap whose rows start at the top.
    private func alpha(_ pixels: [UInt8], x: Int, y: Int) -> UInt8 {
        pixels[((Self.size - 1 - y) * Self.size + x) * 4 + 3]
    }

    @Test("A shadow is filled under the path and spreads out to the blur radius, no further")
    func shadowSpreadsToRadius() {
        let path = NSBezierPath(rect: CGRect(x: 15, y: 15, width: 10, height: 10))
        let pixels = render { path.drawShadow(color: .red, radius: 4) }
        #expect(alpha(pixels, x: 20, y: 20) == 255)
        #expect(alpha(pixels, x: 26, y: 20) > 0, "inside the blur radius")
        #expect(alpha(pixels, x: 31, y: 20) == 0, "the clip stops at the radius")
        #expect(alpha(pixels, x: 2, y: 2) == 0)
    }

    @Test("An empty path or a missing context draws nothing")
    func emptyPathDrawsNothing() {
        let pixels = render { NSBezierPath().drawShadow(color: .red, radius: 4) }
        #expect(pixels.allSatisfy { $0 == 0 })

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nil
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 4, height: 4)).drawShadow(color: .red, radius: 2)
        NSGraphicsContext.restoreGraphicsState()
    }

    @Test("An even-odd path leaves its inner ring unfilled")
    func evenOddHoleStaysEmpty() {
        let path = NSBezierPath(rect: CGRect(x: 5, y: 5, width: 30, height: 30))
        path.append(NSBezierPath(rect: CGRect(x: 15, y: 15, width: 10, height: 10)))
        path.windingRule = .evenOdd
        let pixels = render { path.drawShadow(color: .clear, radius: 0) }
        #expect(alpha(pixels, x: 8, y: 8) == 255)
        #expect(alpha(pixels, x: 20, y: 20) == 0)

        path.windingRule = .nonZero
        let filled = render { path.drawShadow(color: .clear, radius: 0) }
        #expect(alpha(filled, x: 20, y: 20) == 255)
    }

    @Test("A union covers both paths and nothing between them")
    func unionCoversBoth() {
        let left = NSBezierPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        let right = NSBezierPath(rect: CGRect(x: 20, y: 0, width: 10, height: 10))
        let union = left.union(right)
        #expect(union.bounds == CGRect(x: 0, y: 0, width: 30, height: 10))
        #expect(union.contains(CGPoint(x: 5, y: 5)))
        #expect(union.contains(CGPoint(x: 25, y: 5)))
        #expect(!union.contains(CGPoint(x: 15, y: 5)))
    }

    @Test("A union of overlapping paths under either rule fills the overlap")
    func unionOfOverlap() {
        let first = NSBezierPath(rect: CGRect(x: 0, y: 0, width: 20, height: 20))
        let second = NSBezierPath(rect: CGRect(x: 10, y: 10, width: 20, height: 20))
        for rule in [NSBezierPath.WindingRule.evenOdd, .nonZero] {
            let union = first.union(second, using: rule)
            #expect(union.bounds == CGRect(x: 0, y: 0, width: 30, height: 30))
            #expect(union.contains(CGPoint(x: 15, y: 15)))
            #expect(!union.contains(CGPoint(x: 25, y: 5)))
        }
    }
}
