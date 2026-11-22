//
//  ItemsTestFixtures.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// Builders the item tests share.
enum ItemsFixture {
    /// An on-screen item 24 points tall, tagged `tag`, or `title` in the namespace `bundle`,
    /// or `com.example.<title>` without one.
    static func item(
        _ title: String,
        bundle: String? = nil,
        tag: MenuBarItemTag? = nil,
        x: CGFloat = 100,
        y: CGFloat = 0,
        width: CGFloat = 24,
        windowID: CGWindowID = 1,
        ownerPID: pid_t = 100,
        sourcePID: pid_t? = 200,
        isOnScreen: Bool = true
    ) -> MenuBarItem {
        MenuBarItem(
            tag: tag ?? MenuBarItemTag(namespace: .string(bundle ?? "com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: windowID,
            ownerPID: ownerPID,
            sourcePID: sourcePID,
            bounds: CGRect(x: x, y: y, width: width, height: 24),
            title: title,
            isOnScreen: isOnScreen
        )
    }

    /// An RGBA image, clear except `ink` (in pixels, the whole image without one) filled with `color`.
    /// A nil `color` leaves the image clear.
    static func image(
        width: Int,
        height: Int,
        ink: CGRect? = nil,
        color: CGColor? = CGColor(gray: 1, alpha: 1)
    ) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        if let color {
            context.setFillColor(color)
            context.fill(ink ?? CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try #require(context.makeImage())
    }

    /// A glyph capture of `image(width:height:ink:color:)` at `scale`.
    static func glyph(
        width: Int,
        height: Int,
        scale: CGFloat = 1,
        ink: CGRect? = nil,
        color: CGColor? = CGColor(gray: 1, alpha: 1)
    ) throws -> MenuBarItemGlyphCapture {
        try MenuBarItemGlyphCapture(cgImage: image(width: width, height: height, ink: ink, color: color), scale: scale)
    }

    /// A crop `width` by `height` points at `scale`, with ink `inkWidth` by `inkHeight` points
    /// centred in it, filling the crop along a dimension left nil.
    static func centredInkGlyph(
        width: CGFloat,
        height: CGFloat = 16,
        inkWidth: CGFloat? = nil,
        inkHeight: CGFloat? = nil,
        scale: CGFloat = 1,
        color: CGColor? = CGColor(gray: 1, alpha: 1)
    ) throws -> MenuBarItemGlyphCapture {
        let pixelWidth = Int(width * scale), pixelHeight = Int(height * scale)
        let inkColumns = inkWidth.map { Int($0 * scale) } ?? pixelWidth
        let inkRows = inkHeight.map { Int($0 * scale) } ?? pixelHeight
        let ink = CGRect(x: (pixelWidth - inkColumns) / 2, y: (pixelHeight - inkRows) / 2, width: inkColumns, height: inkRows)
        return try glyph(width: pixelWidth, height: pixelHeight, scale: scale, ink: ink, color: color)
    }
}
