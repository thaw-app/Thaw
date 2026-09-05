//
//  ImageHashing.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Perceptual image hashing for the image-comparison trigger condition.
///
/// Uses a simple average hash (aHash): the image is downscaled to 8×8
/// grayscale and each pixel becomes one bit of a 64-bit fingerprint based on
/// whether it is brighter than the image average. Small rendering
/// differences leave the hash mostly unchanged, while a meaningful change
/// (e.g. a notification badge appearing) flips many bits — so comparison via
/// Hamming distance is robust against noise.
enum ImageHashing {
    /// The side length of the downscaled hash grid.
    private static let side = 8

    /// Computes the 64-bit average hash of the given image, or `nil` if the
    /// image can't be rendered.
    static func averageHash(_ image: CGImage) -> UInt64? {
        let count = side * side
        var pixels = [UInt8](repeating: 0, count: count)

        let colorSpace = CGColorSpaceCreateDeviceGray()
        // The buffer is bound for the whole lifetime of the context, not just
        // for the initializer call: `draw` writes through it afterwards. An
        // inout-to-pointer conversion is only valid for the duration of the
        // call it is passed to, so the pointer has to stay in scope instead.
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }

            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard rendered else {
            return nil
        }

        let total = pixels.reduce(0) { $0 + Int($1) }
        let average = total / count

        var hash: UInt64 = 0
        for (index, value) in pixels.enumerated() where Int(value) >= average {
            hash |= (1 << UInt64(index))
        }
        return hash
    }

    /// Computes a stable hash of the image's exact, normalized RGBA pixels.
    /// Unlike ``averageHash``, a one-pixel difference changes this value,
    /// which is appropriate for the opt-in exact comparison mode.
    static func exactHash(_ image: CGImage) -> UInt64? {
        let width = image.width
        let height = image.height
        guard
            width > 0,
            height > 0,
            width <= Int.max / 4
        else {
            return nil
        }

        let bytesPerRow = width * 4
        guard height <= Int.max / bytesPerRow else { return nil }

        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        // The buffer is bound for the whole lifetime of the context, not just
        // for the initializer call: `draw` writes through it afterwards. An
        // inout-to-pointer conversion is only valid for the duration of the
        // call it is passed to, so the pointer has to stay in scope instead.
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else {
            return nil
        }

        // FNV-1a is small, deterministic across launches, and sufficient for
        // change detection. This is not used as a security primitive.
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01B3

        func combine(_ byte: UInt8) {
            hash ^= UInt64(byte)
            hash &*= prime
        }

        for value in [UInt64(width), UInt64(height)] {
            for shift in stride(from: 0, to: 64, by: 8) {
                combine(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
            }
        }
        for byte in pixels {
            combine(byte)
        }
        return hash
    }

    /// The number of differing bits between two hashes (0...64).
    static func hammingDistance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
        (lhs ^ rhs).nonzeroBitCount
    }

    /// The Hamming distance above which two images are considered "changed".
    /// Tuned so anti-aliasing noise is ignored but a badge / state change is
    /// detected on a small menu bar icon.
    static let changeThreshold = 6
}
