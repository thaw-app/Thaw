//
//  GraphicsTestFixtures.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing

/// Builds a premultiplied-first, 32-bit little-endian RGBA image — the shape
/// the capture paths produce — and runs `draw` against its context.
func makeCanvas(
    width: Int,
    height: Int,
    sourceLocation: SourceLocation = #_sourceLocation,
    draw: (CGContext) -> Void
) throws -> CGImage {
    let context = try #require(
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ),
        "Could not create a bitmap context",
        sourceLocation: sourceLocation
    )
    draw(context)
    return try #require(
        context.makeImage(),
        "Could not snapshot the bitmap context",
        sourceLocation: sourceLocation
    )
}

/// Builds an ordinary opaque device-RGB image, for cases where the image
/// itself is not what is under test.
func makeOpaqueImage(
    width: Int,
    height: Int,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> CGImage {
    try makeCanvas(width: width, height: height, sourceLocation: sourceLocation) { context in
        context.setFillColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
}
