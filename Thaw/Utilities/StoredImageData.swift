//
//  StoredImageData.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Image data from a picked file, checked and kept small enough to store in preferences.
nonisolated enum StoredImageData {
    /// Data up to this size is stored as picked, so a small vector image stays sharp.
    static let maximumByteCount = 64 * 1024

    /// The longest side, in pixels, of an image redrawn because its data was too large.
    /// The menu bar draws these images at most 25 points wide, so this covers a 3x display.
    static let maximumPixelLength = 128

    enum Failure: LocalizedError {
        case unreadable

        var errorDescription: String? {
            String(localized: "Thaw can’t read this file as an image.")
        }
    }

    /// The data to store for a picked image: the data itself when it is small, or a
    /// smaller PNG of the image when it is not. Throws when the data isn't an image.
    static func prepared(_ data: Data) throws -> Data {
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
            throw Failure.unreadable
        }
        guard data.count > maximumByteCount else {
            return data
        }
        let scale = Double(maximumPixelLength) / max(image.size.width, image.size.height)
        let width = max(1, Int((image.size.width * scale).rounded()))
        let height = max(1, Int((image.size.height * scale).rounded()))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw Failure.unreadable
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw Failure.unreadable
        }
        return png
    }
}
