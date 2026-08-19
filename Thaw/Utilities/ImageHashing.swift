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
        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        let total = pixels.reduce(0) { $0 + Int($1) }
        let average = total / count

        var hash: UInt64 = 0
        for (index, value) in pixels.enumerated() where Int(value) >= average {
            hash |= (1 << UInt64(index))
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
