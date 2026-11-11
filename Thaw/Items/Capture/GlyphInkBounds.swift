//
//  GlyphInkBounds.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

extension MenuBarItemImageCache {
    /// How far, as a share of the kept glyph's width, the left ink edge may move in before a picture counts as cut.
    static nonisolated let leadingCutTolerance: CGFloat = 0.15

    /// How much solid ink, in points of height, the first pixel column needs before a picture counts
    /// as clipped there. Less is taken for residue of the bar behind the item.
    static nonisolated let leadingClipMinimumInk: CGFloat = 1

    /// The box around the visible ink in points, or nil for a picture with none.
    static nonisolated func inkBounds(of capture: MenuBarItemGlyphCapture) -> CGRect? {
        let image = capture.cgImage
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, capture.scale > 0 else { return nil }
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let context else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let stride = context.bytesPerRow
        var minX = width
        var maxX = -1
        var minY = height
        var maxY = -1
        for row in 0 ..< height {
            for column in 0 ..< width where data[row * stride + column * 4 + 3] > 12 {
                minX = min(minX, column)
                maxX = max(maxX, column)
                minY = min(minY, row)
                maxY = max(maxY, row)
            }
        }
        guard maxX >= minX else { return nil }
        return CGRect(
            x: CGFloat(minX) / capture.scale,
            y: CGFloat(minY) / capture.scale,
            width: CGFloat(maxX - minX + 1) / capture.scale,
            height: CGFloat(maxY - minY + 1) / capture.scale
        )
    }

    /// Whether the picture's ink runs into the left edge of its crop, as when the bar was read while the item
    /// sat left of its frame. An icon that really draws to its edge looks the same.
    static nonisolated func isClippedAtLeadingEdge(_ capture: MenuBarItemGlyphCapture) -> Bool {
        let image = capture.cgImage
        guard image.width > 0, image.height > 0, capture.scale > 0 else { return false }
        // A context one pixel wide keeps only the picture's first column.
        let context = CGContext(
            data: nil,
            width: 1,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let context else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        let stride = context.bytesPerRow
        let solidRows = (0 ..< image.height).count { data[$0 * stride + 3] > 127 }
        return CGFloat(solidRows) / capture.scale >= leadingClipMinimumInk
    }

    /// Whether candidate is the existing picture caught mid-slide: same crop and right edge, left part missing.
    /// Shorter text or a narrower centred symbol doesn't count; identical bytes skip the scan.
    static nonisolated func isLeadingCut(_ candidate: MenuBarItemGlyphCapture, of existing: MenuBarItemGlyphCapture) -> Bool {
        guard abs(candidate.pointSize.width - existing.pointSize.width) < 1,
              candidate.cgImage !== existing.cgImage,
              candidate.cgImage.dataProvider?.data != existing.cgImage.dataProvider?.data,
              let kept = inkBounds(of: existing), let new = inkBounds(of: candidate)
        else { return false }
        let edgeSlack = max(1, kept.width * 0.05)
        return abs(new.maxX - kept.maxX) <= edgeSlack && new.minX - kept.minX > kept.width * leadingCutTolerance
    }
}
