//
//  Image+PNG.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import ImageIO
import UniformTypeIdentifiers

extension CGImage {
    /// The image encoded as PNG, or nil when ImageIO can't encode it.
    nonisolated func pngData() -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, self, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Writes the image to url as PNG, and returns whether ImageIO finished the file.
    nonisolated func writePNG(to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, self, nil)
        return CGImageDestinationFinalize(destination)
    }
}

extension NSImage {
    /// The image drawn to fill an RGBA bitmap of the given pixel size, encoded as PNG.
    ///
    /// - Parameter pointSize: The bitmap's size in points, so the PNG records its pixel
    ///   density. Without one, a point is a pixel.
    nonisolated func pngData(pixelsWide: Int, pixelsHigh: Int, pointSize: NSSize? = nil) -> Data? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        let size = pointSize ?? NSSize(width: pixelsWide, height: pixelsHigh)
        bitmap.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
