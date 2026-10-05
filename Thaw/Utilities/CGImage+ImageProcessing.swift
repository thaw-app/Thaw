//
//  CGImage+ImageProcessing.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

extension CGImage {
    // MARK: Average Color

    /// Adjustments to how averageColor(using:alphaThreshold:option:) treats
    /// the pixels it reads.
    nonisolated struct ColorAveragingOption: OptionSet {
        let rawValue: Int

        /// Report the average as fully opaque rather than averaging the alpha
        /// component alongside the color components.
        static let ignoreAlpha = ColorAveragingOption(rawValue: 1)
    }

    /// Returns roughly the average color of the image.
    ///
    /// The image is scaled down to at most 10×10 pixels before its pixels are
    /// summed, so the result is an approximation, cheap enough to recompute
    /// whenever the image changes.
    ///
    /// - Parameters:
    ///   - colorSpace: An RGB color space to average in, which is also the
    ///     color space of the returned color. Ignored unless it is an RGB
    ///     space, in which case a suitable space is chosen automatically.
    ///   - alphaThreshold: Pixels whose alpha component falls below this value
    ///     are left out of the average entirely.
    ///   - option: Adjustments to how the average is computed.
    ///
    /// - Returns: The average color, or nil if the image could not be read.
    nonisolated func averageColor(using colorSpace: CGColorSpace? = nil, alphaThreshold: CGFloat = 0.5, option: ColorAveragingOption = []) -> CGColor? {
        let space = averagingColorSpace(preferring: colorSpace)

        // Sampling a handful of pixels is close enough, and far cheaper.
        let sampleWidth = min(width, 10)
        let sampleHeight = min(height, 10)

        guard let pixels = downsampledPixels(width: sampleWidth, height: sampleHeight, in: space) else {
            return nil
        }

        // Components arrive as bytes, so the threshold is lifted onto the same
        // 0...255 scale rather than the components being pushed down onto its.
        let minimumAlpha = UInt64((alphaThreshold.clamped(to: 0 ... 1) * 255).rounded(.toNearestOrAwayFromZero))

        var sampleCount = UInt64(sampleWidth * sampleHeight)
        var sums = (red: UInt64(0), green: UInt64(0), blue: UInt64(0), alpha: UInt64(0))

        for pixel in pixels {
            let (alpha, red, green, blue) = Self.unpackARGB(pixel)
            guard alpha >= minimumAlpha else {
                sampleCount -= 1 // Too faint to count towards the average.
                continue
            }
            sums.red += red
            sums.green += green
            sums.blue += blue
            sums.alpha += alpha
        }

        guard sampleCount > 0 else {
            return nil // Every pixel fell below the alpha threshold.
        }

        // Every sum totals byte-sized components, so scaling the pixel count up
        // by 255 lands the quotients straight in the 0...1 range CGColor wants.
        let divisor = CGFloat(sampleCount * 255)
        func normalized(_ sum: UInt64) -> CGFloat {
            CGFloat(sum) / divisor
        }
        var components = [
            normalized(sums.red),
            normalized(sums.green),
            normalized(sums.blue),
            option.contains(.ignoreAlpha) ? 1 : normalized(sums.alpha),
        ]

        return CGColor(colorSpace: space, components: &components)
    }

    /// Draws the image into a scratch bitmap of the given size and hands back
    /// its pixels, one packed ARGB word each.
    private nonisolated func downsampledPixels(width: Int, height: Int, in colorSpace: CGColorSpace) -> [UInt32]? {
        guard width > 0, height > 0 else {
            return nil
        }
        var pixels = [UInt32](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(alpha: .premultipliedFirst, byteOrder: .order32Little)
            ) else {
                return false
            }
            context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }

    /// Picks the RGB color space to average in: the caller's choice if it is an
    /// RGB space, otherwise the image's own, otherwise Display P3.
    private nonisolated func averagingColorSpace(preferring requested: CGColorSpace?) -> CGColorSpace {
        for candidate in [requested, colorSpace] {
            if let candidate, candidate.model == .rgb {
                return candidate
            }
        }
        return CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
    }

    /// Splits a packed ARGB word into its four byte-sized channels, each
    /// widened to UInt64 so they can be summed without overflow.
    private static nonisolated func unpackARGB(_ pixel: UInt32) -> (alpha: UInt64, red: UInt64, green: UInt64, blue: UInt64) {
        (
            alpha: UInt64(pixel >> 24 & 0xFF),
            red: UInt64(pixel >> 16 & 0xFF),
            green: UInt64(pixel >> 8 & 0xFF),
            blue: UInt64(pixel & 0xFF)
        )
    }

    // MARK: Trimming Transparency

    /// A bounds-validated, read-only view over the alpha channel of
    /// row-major pixel data.
    ///
    /// The failable initializer bounds-checks the geometry so scans cannot
    /// read out of bounds. Must not outlive the memory it wraps.
    private nonisolated struct AlphaChannelView {
        private let bytes: UnsafeRawBufferPointer
        private let rowStride: Int
        private let pixelStride: Int
        private let alphaOffset: Int

        /// The byte value above which a pixel counts as opaque.
        private let threshold: UInt8

        /// The image width, in pixels.
        let width: Int

        /// The image height, in pixels.
        let height: Int

        /// Creates a view if every alpha byte addressed by the given
        /// geometry lies within bytes.
        ///
        /// - Parameters:
        ///   - bytes: The pixel data.
        ///   - width: The image width, in pixels.
        ///   - height: The image height, in pixels.
        ///   - rowStride: The number of bytes per row, including padding.
        ///   - pixelStride: The number of bytes per pixel.
        ///   - alphaOffset: The offset of the alpha byte within each pixel.
        ///   - alphaThreshold: The maximum alpha value (0...1) to consider
        ///     transparent.
        init?(
            bytes: UnsafeRawBufferPointer,
            width: Int,
            height: Int,
            rowStride: Int,
            pixelStride: Int,
            alphaOffset: Int,
            alphaThreshold: CGFloat
        ) {
            guard
                width > 0,
                height > 0,
                pixelStride > 0,
                (0 ..< pixelStride).contains(alphaOffset),
                rowStride >= width * pixelStride,
                bytes.count >= (height - 1) * rowStride + (width - 1) * pixelStride + alphaOffset + 1
            else {
                return nil
            }
            self.bytes = bytes
            self.width = width
            self.height = height
            self.rowStride = rowStride
            self.pixelStride = pixelStride
            self.alphaOffset = alphaOffset
            self.threshold = UInt8(min(max(alphaThreshold * 255, 0), 255))
        }

        func isPixelOpaque(row: Int, column: Int) -> Bool {
            bytes[(row * rowStride) + (column * pixelStride) + alphaOffset] > threshold
        }

        func isRowTransparent(_ row: Int) -> Bool {
            !(0 ..< width).contains { isPixelOpaque(row: row, column: $0) }
        }

        func isColumnTransparent(_ column: Int) -> Bool {
            !(0 ..< height).contains { isPixelOpaque(row: $0, column: column) }
        }

        func isTransparent() -> Bool {
            (0 ..< height).allSatisfy(isRowTransparent)
        }

        func firstOpaqueRow(in rows: some Sequence<Int>) -> Int? {
            rows.first { !isRowTransparent($0) }
        }

        func firstOpaqueColumn(in columns: some Sequence<Int>) -> Int? {
            columns.first { !isColumnTransparent($0) }
        }
    }

    /// A scratch alpha-channel rendering of an image, used to find where its
    /// transparent margins end.
    private nonisolated struct AlphaMask {
        private let image: CGImage
        /// Retained to keep the memory backing alphaView alive.
        private let cgContext: CGContext
        private let alphaView: AlphaChannelView

        /// Renders image into an alpha-only bitmap and wraps it in a view
        /// that can be scanned for opaque pixels.
        ///
        /// Fails when the image has no area, when alphaThreshold is high
        /// enough that nothing could ever count as opaque, or when the scratch
        /// bitmap cannot be allocated.
        ///
        /// - Parameters:
        ///   - image: The image to scan.
        ///   - alphaThreshold: The alpha value at or below which a pixel is
        ///     treated as fully see-through.
        init?(of image: CGImage, alphaThreshold: CGFloat) {
            guard image.width > 0, image.height > 0, alphaThreshold < 1 else {
                return nil
            }

            guard
                let cgContext = CGContext(
                    data: nil,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGBitmapInfo(alpha: .alphaOnly)
                ),
                let data = cgContext.data
            else {
                return nil
            }

            cgContext.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

            // The context owns data for the lifetime of cgContext, which
            // this struct retains, so the view can't outlive its memory.
            guard let alphaView = AlphaChannelView(
                bytes: UnsafeRawBufferPointer(
                    start: data,
                    count: cgContext.bytesPerRow * cgContext.height
                ),
                width: image.width,
                height: image.height,
                rowStride: cgContext.bytesPerRow,
                pixelStride: 1,
                alphaOffset: 0,
                alphaThreshold: alphaThreshold
            ) else {
                return nil
            }

            self.image = image
            self.cgContext = cgContext
            self.alphaView = alphaView
        }

        /// Returns the mask's image with its transparent margins cut away from
        /// the given edges.
        ///
        /// Edges not requested are never scanned.
        ///
        /// - Returns: The cropped image, the original image when every
        ///   requested edge is already tight, or nil when no pixel anywhere
        ///   is opaque.
        func croppingTransparentMargins(from edges: Set<CGRectEdge>) -> CGImage? {
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            var box = bounds

            for edge in edges {
                // A nil depth means the scan crossed the whole image without
                // hitting an opaque pixel, so nothing would survive the crop.
                guard let depth = transparencyDepth(at: edge) else {
                    return nil
                }
                let inset = CGFloat(depth)
                switch edge {
                case .minXEdge:
                    box.origin.x += inset
                    box.size.width -= inset
                case .maxXEdge:
                    box.size.width -= inset
                case .minYEdge:
                    box.origin.y += inset
                    box.size.height -= inset
                case .maxYEdge:
                    box.size.height -= inset
                }
            }

            if box == bounds {
                return image // Already tight against its content.
            }
            return image.cropping(to: box)
        }

        /// Whether every pixel of the mask's image counts as transparent.
        func isTransparent() -> Bool {
            alphaView.isTransparent()
        }

        /// How deep the transparency resting against one edge runs, measured
        /// in rows or columns from that edge to the first opaque pixel.
        ///
        /// - Returns: nil when the image holds no opaque pixel at all.
        private func transparencyDepth(at edge: CGRectEdge) -> Int? {
            let rows = 0 ..< image.height
            let columns = 0 ..< image.width
            return switch edge {
            case .minXEdge:
                alphaView.firstOpaqueColumn(in: columns)
            case .maxXEdge:
                alphaView.firstOpaqueColumn(in: columns.reversed()).map { columns.upperBound - 1 - $0 }
            case .minYEdge:
                alphaView.firstOpaqueRow(in: rows)
            case .maxYEdge:
                alphaView.firstOpaqueRow(in: rows.reversed()).map { rows.upperBound - 1 - $0 }
            }
        }
    }

    /// Returns a copy of the image with its transparent margins cut away from
    /// the given edges.
    ///
    /// Each edge is cut in as far as the first row or column holding a pixel
    /// whose alpha component rises above the threshold.
    ///
    /// - Parameters:
    ///   - edges: The edges to cut in from.
    ///   - alphaThreshold: The highest alpha value that still counts as
    ///     transparent.
    ///
    /// - Returns: The cropped image, or nil when nothing opaque remains.
    func trimmingTransparency(
        around edges: Set<CGRectEdge> = [.minXEdge, .minYEdge, .maxXEdge, .maxYEdge],
        alphaThreshold: CGFloat = 0
    ) -> CGImage? {
        guard let mask = AlphaMask(of: self, alphaThreshold: alphaThreshold) else {
            return self
        }
        return mask.croppingTransparentMargins(from: edges)
    }

    /// What separating an image from its near-uniform background found.
    nonisolated enum GlyphPresence {
        /// A glyph survived the knock-out.
        case present
        /// Everything, or all but a negligible speckle, matched the background:
        /// the crop holds bar fill and nothing else.
        case absent
        /// Glyph and background could not be separated, as on busy or
        /// gradient wallpapers.
        case indeterminate
    }

    /// Makes near-uniform menu-bar fill around a glyph transparent.
    ///
    /// Reads the background from the 1px edge ring and clears pixels within
    /// maxColorDistance (0…441 Euclidean RGB) of it. Returns nil when the image
    /// already looks transparent or nothing would survive.
    ///
    /// - Parameter maxColorDistance: Maximum RGB distance from the sampled
    ///   background treated as fill to clear.
    nonisolated func knockingOutNearUniformBackground(
        maxColorDistance: CGFloat = 36
    ) -> CGImage? {
        let separated = separatedFromNearUniformBackground(maxColorDistance: maxColorDistance)
        guard separated.presence == .present else { return nil }
        return separated.image
    }

    /// Whether a glyph sits on the near-uniform background this crop was cut
    /// from, or nothing does, or it cannot be told.
    ///
    /// Like knockingOutNearUniformBackground(maxColorDistance:), but tells an
    /// empty slot from an unreadable crop, which that method's nil conflates.
    ///
    /// - Parameter maxColorDistance: Maximum RGB distance from the sampled
    ///   background treated as fill to clear.
    nonisolated func glyphPresenceOverNearUniformBackground(
        maxColorDistance: CGFloat = 36
    ) -> GlyphPresence {
        separatedFromNearUniformBackground(maxColorDistance: maxColorDistance).presence
    }

    nonisolated func separatedFromNearUniformBackground(
        maxColorDistance: CGFloat = 36,
        allowsInset: Bool = true
    ) -> (image: CGImage?, presence: GlyphPresence) {
        guard width > 2, height > 2, maxColorDistance > 0 else { return (nil, .indeterminate) }

        let bytesPerPixel = 4
        guard let (context, initialPixels, bytesPerRow) = Self.editableBitmap(of: self) else {
            return (nil, .indeterminate)
        }
        var pixels = initialPixels

        // The mode over the whole edge ring, not the corners: a tight glyph
        // touches the corners. 8 levels per channel absorb anti-aliasing.
        guard let ring = Self.estimateEdgeRing(
            pixels: pixels,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            bytesPerPixel: bytesPerPixel
        ) else {
            return (nil, .indeterminate)
        }

        // A full-height frame reaches past the item pill into the wallpaper.
        // When a ring a few pixels in agrees on one fill, separate inside it.
        if allowsInset, ring.majorityShare < 0.6,
           let inset = Self.betterFillInset(
               pixels: pixels,
               width: width,
               height: height,
               bytesPerRow: bytesPerRow,
               bytesPerPixel: bytesPerPixel,
               outerShare: ring.majorityShare
           ),
           let inner = cropping(to: CGRect(x: inset, y: inset, width: width - 2 * inset, height: height - 2 * inset))
        {
            return inner.separatedFromNearUniformBackground(
                maxColorDistance: maxColorDistance,
                allowsInset: false
            )
        }
        // Without one dominant bucket the background varies, and a single
        // colour would leave most of it as glyph, so model it locally.
        let varyingBackground = ring.majorityShare < 0.4
        let maxDistSq = maxColorDistance * maxColorDistance

        let background = BackgroundModel(ring: ring, varying: varyingBackground)

        let tally = Self.classify(
            pixels: &pixels,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            bytesPerPixel: bytesPerPixel,
            background: background,
            maxDistSq: maxDistSq
        )

        if let verdict = Self.glyphVerdict(
            pixels: pixels,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            bytesPerPixel: bytesPerPixel,
            tally: tally,
            varyingBackground: varyingBackground,
            majorityShare: ring.majorityShare,
            maxColorDistance: maxColorDistance
        ) {
            return (nil, verdict)
        }

        Self.matteAntialiasedEdges(
            pixels: &pixels,
            keptPixels: tally.keptPixels,
            maxColorDistance: maxColorDistance
        )
        return (Self.image(from: context, pixels: pixels), .present)
    }

    /// The background a crop is knocked out against: the dominant ring colour,
    /// the palette of nearby tiles, and whether the background varies enough to
    /// be modelled locally.
    private nonisolated struct BackgroundModel {
        private let fill: (r: Int, g: Int, b: Int)
        private let palette: [(r: Int, g: Int, b: Int)]
        private let varying: Bool
        private let width: Int
        private let height: Int
        private let topRow: [(r: Int, g: Int, b: Int)?]
        private let bottomRow: [(r: Int, g: Int, b: Int)?]
        private let leftColumn: [(r: Int, g: Int, b: Int)?]
        private let rightColumn: [(r: Int, g: Int, b: Int)?]

        init(ring: EdgeRingReading, varying: Bool) {
            self.fill = (ring.r, ring.g, ring.b)
            self.palette = ring.palette
            self.varying = varying
            self.width = ring.topRow.count
            self.height = ring.leftColumn.count
            self.topRow = ring.topRow
            self.bottomRow = ring.bottomRow
            self.leftColumn = ring.leftColumn
            self.rightColumn = ring.rightColumn
        }

        /// A checker or tiled wallpaper has a second tone near the fill; one
        /// colour alone clears only its own tiles.
        private func nearestPaletteColour(r: Int, g: Int, b: Int) -> (r: Int, g: Int, b: Int) {
            var best = fill
            var bestDistSq = (r - fill.r) * (r - fill.r) + (g - fill.g) * (g - fill.g) + (b - fill.b) * (b - fill.b)
            for tone in palette {
                let distSq = (r - tone.r) * (r - tone.r) + (g - tone.g) * (g - tone.g) + (b - tone.b) * (b - tone.b)
                if distSq < bestDistSq {
                    best = tone
                    bestDistSq = distSq
                }
            }
            return best
        }

        /// The edge ring's colour at this pixel, weighted towards the closest
        /// edge so a gradient is followed. Falls back to the dominant colour.
        private func localBackground(x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
            var rSum = 0.0
            var gSum = 0.0
            var bSum = 0.0
            var weightSum = 0.0
            func add(_ sample: (r: Int, g: Int, b: Int)?, weight: Double) {
                guard let sample else { return }
                rSum += Double(sample.r) * weight
                gSum += Double(sample.g) * weight
                bSum += Double(sample.b) * weight
                weightSum += weight
            }
            add(topRow[x], weight: 1.0 / Double(y + 1))
            add(bottomRow[x], weight: 1.0 / Double(height - y))
            add(leftColumn[y], weight: 1.0 / Double(x + 1))
            add(rightColumn[y], weight: 1.0 / Double(width - x))
            guard weightSum > 0 else { return fill }
            return (
                Int((rSum / weightSum).rounded()),
                Int((gSum / weightSum).rounded()),
                Int((bSum / weightSum).rounded())
            )
        }

        private func distanceSquared(_ r: Int, _ g: Int, _ b: Int, to c: (r: Int, g: Int, b: Int)) -> CGFloat {
            let dr = CGFloat(r - c.r)
            let dg = CGFloat(g - c.g)
            let db = CGFloat(b - c.b)
            return dr * dr + dg * dg + db * db
        }

        /// The reference colour for a pixel and its distance from it. A
        /// gradient is followed locally, tiles by the palette; the closer of
        /// the two is this pixel's background.
        func reference(
            r: Int,
            g: Int,
            b: Int,
            x: Int,
            y: Int
        ) -> (colour: (r: Int, g: Int, b: Int), distanceSquared: CGFloat) {
            var best = nearestPaletteColour(r: r, g: g, b: b)
            var bestDistSq = distanceSquared(r, g, b, to: best)
            if varying {
                let local = localBackground(x: x, y: y)
                let localDistSq = distanceSquared(r, g, b, to: local)
                if localDistSq < bestDistSq {
                    best = local
                    bestDistSq = localDistSq
                }
            }
            return (best, bestDistSq)
        }
    }

    /// What a background knock-out pass cleared and kept.
    private nonisolated struct KnockoutTally {
        var cleared = 0
        var kept = 0
        /// Per-row and per-column tallies of kept pixels. A glyph builds a
        /// dense row or column; surviving wallpaper noise spreads evenly.
        var perRowKept: [Int] = []
        var perColKept: [Int] = []
        /// Each kept pixel's background and distance from it, for the matte.
        var keptPixels: [(index: Int, reference: (r: Int, g: Int, b: Int), distance: CGFloat)] = []
    }

    /// Clears every pixel whose colour lies within maxDistSq of the background
    /// model and tallies what survives.
    private static nonisolated func classify(
        pixels: inout [UInt8],
        width: Int,
        height: Int,
        bytesPerRow: Int,
        bytesPerPixel: Int,
        background: BackgroundModel,
        maxDistSq: CGFloat
    ) -> KnockoutTally {
        var tally = KnockoutTally(
            perRowKept: [Int](repeating: 0, count: height),
            perColKept: [Int](repeating: 0, count: width)
        )
        for y in 0 ..< height {
            for x in 0 ..< width {
                let i = y * bytesPerRow + x * bytesPerPixel
                guard let sample = Self.unPremultipliedColour(pixels, at: i) else {
                    pixels[i] = 0
                    pixels[i + 1] = 0
                    pixels[i + 2] = 0
                    pixels[i + 3] = 0
                    tally.cleared += 1
                    continue
                }
                let reference = background.reference(r: sample.r, g: sample.g, b: sample.b, x: x, y: y)
                if reference.distanceSquared <= maxDistSq {
                    pixels[i] = 0
                    pixels[i + 1] = 0
                    pixels[i + 2] = 0
                    pixels[i + 3] = 0
                    tally.cleared += 1
                } else {
                    tally.kept += 1
                    tally.perRowKept[y] += 1
                    tally.perColKept[x] += 1
                    tally.keptPixels.append((i, reference.colour, reference.distanceSquared.squareRoot()))
                }
            }
        }
        return tally
    }

    /// Sizes of the 4-connected components of kept pixels, in scan order.
    ///
    /// A glyph is one or two coherent shapes, while wallpaper that survives
    /// the colour knock-out is a scatter of patches, because no colour model
    /// follows a photographic background.
    static nonisolated func connectedComponentSizes(
        width: Int,
        height: Int,
        isKept: (Int, Int) -> Bool
    ) -> [Int] {
        var visited = [Bool](repeating: false, count: width * height)
        var sizes = [Int]()
        var stack = [Int]()
        for start in 0 ..< (width * height) where !visited[start] {
            visited[start] = true
            let startX = start % width
            let startY = start / width
            guard isKept(startX, startY) else { continue }
            var size = 0
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            while let index = stack.popLast() {
                size += 1
                let x = index % width
                let y = index / width
                if x > 0, !visited[index - 1], isKept(x - 1, y) {
                    visited[index - 1] = true
                    stack.append(index - 1)
                }
                if x + 1 < width, !visited[index + 1], isKept(x + 1, y) {
                    visited[index + 1] = true
                    stack.append(index + 1)
                }
                if y > 0, !visited[index - width], isKept(x, y - 1) {
                    visited[index - width] = true
                    stack.append(index - width)
                }
                if y + 1 < height, !visited[index + width], isKept(x, y + 1) {
                    visited[index + width] = true
                    stack.append(index + width)
                }
            }
            sizes.append(size)
        }
        return sizes
    }

    /// Runs the knock-out's acceptance gates in order and returns a verdict,
    /// or nil when the crop passes them all.
    ///
    /// The absent case is decided before the indeterminate ones so a caller
    /// can tell an empty slot from an unreadable crop.
    private static nonisolated func glyphVerdict(
        pixels: [UInt8],
        width: Int,
        height: Int,
        bytesPerRow: Int,
        bytesPerPixel: Int,
        tally: KnockoutTally,
        varyingBackground: Bool,
        majorityShare: Double,
        maxColorDistance: CGFloat
    ) -> GlyphPresence? {
        // Nothing, or only speckle, survived: the crop is bar fill.
        guard tally.kept > 0, Double(tally.kept) / Double(tally.kept + tally.cleared) >= 0.02 else {
            return .absent
        }
        // Nothing cleared: the edge ring never agreed on a background.
        guard tally.cleared > 0 else { return .indeterminate }

        // A glyph has a column covering a third of the height or a row
        // covering a fifth of the width; wallpaper noise builds neither.
        let maxColumnKept = tally.perColKept.max() ?? 0
        let maxRowKept = tally.perRowKept.max() ?? 0
        let columnThreshold = max(1, height / 3)
        let rowThreshold = max(1, width / 5)
        guard maxColumnKept >= columnThreshold || maxRowKept >= rowThreshold else {
            return .indeterminate
        }

        // The largest connected component must dominate: a scatter is not a glyph.
        let componentSizes = Self.connectedComponentSizes(width: width, height: height) { x, y in
            pixels[y * bytesPerRow + x * bytesPerPixel + 3] > 8
        }
        // A one-colour ring is a solid bar, not wallpaper, so text and dot
        // grids may be many shapes. Elsewhere the largest shape still has to
        // lead, with room for three even parts such as a play-pause glyph or
        // a row of keys.
        let solidFill = majorityShare >= 0.95
        guard !componentSizes.isEmpty,
              solidFill
              || (componentSizes.count <= 6 && (componentSizes.max() ?? 0) * 10 >= tally.kept * 3)
              || Self.looksLikeInk(
                  componentSizes: componentSizes,
                  kept: tally.kept,
                  keptDistances: tally.keptPixels.map(\.distance),
                  maxColorDistance: maxColorDistance,
                  imageArea: width * height
              )
        else {
            return .indeterminate
        }

        // On a varying background the local model must explain most of the
        // crop; otherwise what survived is background it could not follow.
        if varyingBackground {
            let opaque = tally.kept + tally.cleared
            guard opaque > 0, Double(tally.cleared) / Double(opaque) >= 0.5 else {
                return .indeterminate
            }
        }
        return nil
    }

    /// Draws the image into a premultiplied RGBA8 scratch bitmap and hands
    /// back the context, its pixels, and the row stride.
    ///
    /// The context owns its memory, since a &pixels argument is only valid for
    /// the init call. Pixels are copied out, edited, and copied back.
    private static nonisolated func editableBitmap(
        of image: CGImage
    ) -> (context: CGContext, pixels: [UInt8], bytesPerRow: Int)? {
        guard image.width > 0, image.height > 0 else { return nil }
        let bytesPerRow = image.width * 4
        let byteCount = bytesPerRow * image.height
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let contextData = context.data else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = [UInt8](UnsafeRawBufferPointer(start: contextData, count: byteCount))
        return (context, pixels, bytesPerRow)
    }

    /// Copies edited pixels back into the context's bitmap and returns the
    /// resulting image.
    private static nonisolated func image(from context: CGContext, pixels: [UInt8]) -> CGImage? {
        guard let contextData = context.data else { return nil }
        pixels.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            contextData.copyMemory(from: baseAddress, byteCount: pixels.count)
        }
        return context.makeImage()
    }

    /// Un-premultiplies the pixel at byte offset i, or nil when it is too faint
    /// to read a colour from.
    private static nonisolated func unPremultipliedColour(
        _ pixels: [UInt8],
        at i: Int
    ) -> (r: Int, g: Int, b: Int, a: Int)? {
        let a = Int(pixels[i + 3])
        guard a > 8 else { return nil }
        return (
            r: Int(pixels[i]) * 255 / a,
            g: Int(pixels[i + 1]) * 255 / a,
            b: Int(pixels[i + 2]) * 255 / a,
            a: a
        )
    }

    /// The smallest inset, up to a sixth of the shorter side, whose ring
    /// agrees on one fill clearly better than the outer ring does.
    private static nonisolated func betterFillInset(
        pixels: [UInt8],
        width: Int,
        height: Int,
        bytesPerRow: Int,
        bytesPerPixel: Int,
        outerShare: Double
    ) -> Int? {
        let maximumInset = min(8, min(width, height) / 6)
        guard maximumInset >= 1 else { return nil }
        for inset in 1 ... maximumInset {
            let innerWidth = width - 2 * inset
            let innerHeight = height - 2 * inset
            guard innerWidth > 2, innerHeight > 2 else { return nil }
            var inner = [UInt8](repeating: 0, count: innerWidth * innerHeight * bytesPerPixel)
            for y in 0 ..< innerHeight {
                let source = (y + inset) * bytesPerRow + inset * bytesPerPixel
                let target = y * innerWidth * bytesPerPixel
                inner.replaceSubrange(
                    target ..< target + innerWidth * bytesPerPixel,
                    with: pixels[source ..< source + innerWidth * bytesPerPixel]
                )
            }
            guard let reading = estimateEdgeRing(
                pixels: inner,
                width: innerWidth,
                height: innerHeight,
                bytesPerRow: innerWidth * bytesPerPixel,
                bytesPerPixel: bytesPerPixel
            ) else { continue }
            if reading.majorityShare >= 0.6, reading.majorityShare >= outerShare + 0.2 {
                return inset
            }
        }
        return nil
    }

    /// Whether many surviving shapes are text or a dot grid rather than
    /// wallpaper the colour model could not follow.
    ///
    /// Surviving wallpaper is specks close to the background colour; ink is
    /// shapes of some size, part of which stands far from it. Both must hold.
    static nonisolated func looksLikeInk(
        componentSizes: [Int],
        kept: Int,
        keptDistances: [CGFloat],
        maxColorDistance: CGFloat,
        imageArea: Int
    ) -> Bool {
        guard kept > 0, !keptDistances.isEmpty else { return false }
        // A speck is under a thousandth of the crop, at least a few pixels.
        let speck = max(6, imageArea / 1000)
        let inShapes = componentSizes.filter { $0 > speck }.reduce(0, +)
        guard inShapes * 10 >= kept * 8 else { return false }
        // The upper quartile, not the median: a status glyph can be mostly
        // dimmed marks (inactive dots) around a few at full ink.
        let sorted = keptDistances.sorted()
        let upperQuartile = sorted[sorted.count * 3 / 4]
        return upperQuartile >= maxColorDistance * 2.5
    }

    /// Turns the glyph's anti-aliased rim from opaque into partly transparent.
    ///
    /// Kept opaque, a rim pixel carries the bar's colour as a halo. Its alpha
    /// is its distance from the background relative to the ink.
    private static nonisolated func matteAntialiasedEdges(
        pixels: inout [UInt8],
        keptPixels: [(index: Int, reference: (r: Int, g: Int, b: Int), distance: CGFloat)],
        maxColorDistance: CGFloat
    ) {
        guard !keptPixels.isEmpty else { return }
        // Full ink is what most of the glyph reaches; a fixed contrast would
        // fade a low-contrast glyph as a whole.
        let distances = keptPixels.map(\.distance).sorted()
        let inkDistance = distances[distances.count * 3 / 4]
        let fadeRange = inkDistance - maxColorDistance
        guard fadeRange > maxColorDistance / 2 else { return }
        for pixel in keptPixels where pixel.distance < inkDistance {
            let coverage = (pixel.distance - maxColorDistance) / fadeRange
            let alpha = min(1, max(1.0 / 255, coverage))
            let i = pixel.index
            let a = CGFloat(pixels[i + 3]) / 255
            let background = [pixel.reference.r, pixel.reference.g, pixel.reference.b]
            for channel in 0 ..< 3 {
                let observed = CGFloat(pixels[i + channel]) / max(a, 1.0 / 255)
                let ink = (observed - (1 - alpha) * CGFloat(background[channel])) / alpha
                let clampedInk = min(255, max(0, ink))
                pixels[i + channel] = UInt8((clampedInk * alpha * a).rounded())
            }
            pixels[i + 3] = UInt8((alpha * a * 255).rounded())
        }
    }

    /// The edge-ring reading behind the background knock-out: the
    /// dominant fill colour, how much of the ring backs it, and the four edge
    /// profiles a varying background can be modelled from.
    ///
    /// A high majorityShare means a single fill colour models the background;
    /// a low one means a gradient or pattern.
    nonisolated struct EdgeRingReading {
        let r: Int
        let g: Int
        let b: Int
        /// Share of opaque ring pixels that fell in the winning bucket, 0…1.
        let majorityShare: Double
        /// Other well-supported ring tones near the fill: the second tile of a
        /// checker or tiled wallpaper. Empty on a plain bar.
        let palette: [(r: Int, g: Int, b: Int)]
        /// One un-premultiplied sample per x, nil where the edge is transparent.
        let topRow: [(r: Int, g: Int, b: Int)?]
        let bottomRow: [(r: Int, g: Int, b: Int)?]
        /// One un-premultiplied sample per y, nil where the edge is transparent.
        let leftColumn: [(r: Int, g: Int, b: Int)?]
        let rightColumn: [(r: Int, g: Int, b: Int)?]
    }

    static nonisolated func estimateEdgeRing(
        pixels: [UInt8],
        width: Int,
        height: Int,
        bytesPerRow: Int,
        bytesPerPixel: Int
    ) -> EdgeRingReading? {
        guard width > 2, height > 2 else { return nil }

        // Coarse bucket key: top 5 bits of each un-premultiplied channel,
        // packed into an Int. 8 levels per channel = 512 buckets, enough to
        // separate a bar fill from a glyph while merging AA fringes.

        func bucket(of r: Int, g: Int, b: Int) -> Int {
            (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
        }

        func sample(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int)? {
            let i = y * bytesPerRow + x * bytesPerPixel
            guard let sample = Self.unPremultipliedColour(pixels, at: i) else { return nil }
            return (r: sample.r, g: sample.g, b: sample.b)
        }

        var topRow = [(r: Int, g: Int, b: Int)?](repeating: nil, count: width)
        var bottomRow = [(r: Int, g: Int, b: Int)?](repeating: nil, count: width)
        var leftColumn = [(r: Int, g: Int, b: Int)?](repeating: nil, count: height)
        var rightColumn = [(r: Int, g: Int, b: Int)?](repeating: nil, count: height)
        for x in 0 ..< width {
            topRow[x] = sample(x, 0)
            bottomRow[x] = sample(x, height - 1)
        }
        for y in 0 ..< height {
            leftColumn[y] = sample(0, y)
            rightColumn[y] = sample(width - 1, y)
        }

        var voteCounts: [Int: Int] = [:]
        var voteSums: [Int: (r: Int, g: Int, b: Int, n: Int)] = [:]
        var totalVotes = 0
        for (x, y) in Self.edgeRingPositions(width: width, height: height) {
            guard let c = sample(x, y) else { continue }
            let key = bucket(of: c.r, g: c.g, b: c.b)
            totalVotes += 1
            voteCounts[key, default: 0] += 1
            var sum = voteSums[key] ?? (r: 0, g: 0, b: 0, n: 0)
            sum.r += c.r
            sum.g += c.g
            sum.b += c.b
            sum.n += 1
            voteSums[key] = sum
        }
        guard totalVotes > 0 else { return nil }

        let winningBucket = voteCounts.max(by: { $0.value < $1.value })?.key ?? 0
        guard let sum = voteSums[winningBucket], sum.n > 0 else { return nil }
        let fill = (r: sum.r / sum.n, g: sum.g / sum.n, b: sum.b / sum.n)

        // Enough ring support to be background, and near the fill: tiles
        // differ by tens of units, a glyph from its bar by hundreds.
        let minimumSupport = max(2, totalVotes / 20)
        let maximumSpread = 72
        let palette = voteSums.compactMap { key, bucketSum -> (r: Int, g: Int, b: Int)? in
            guard key != winningBucket, bucketSum.n >= minimumSupport else { return nil }
            let tone = (r: bucketSum.r / bucketSum.n, g: bucketSum.g / bucketSum.n, b: bucketSum.b / bucketSum.n)
            let dr = tone.r - fill.r
            let dg = tone.g - fill.g
            let db = tone.b - fill.b
            guard dr * dr + dg * dg + db * db <= maximumSpread * maximumSpread else { return nil }
            return tone
        }
        return EdgeRingReading(
            r: fill.r,
            g: fill.g,
            b: fill.b,
            majorityShare: Double(sum.n) / Double(totalVotes),
            palette: palette,
            topRow: topRow,
            bottomRow: bottomRow,
            leftColumn: leftColumn,
            rightColumn: rightColumn
        )
    }

    /// The 1px perimeter in row-first order, each pixel visited once.
    private static nonisolated func edgeRingPositions(
        width: Int,
        height: Int
    ) -> [(x: Int, y: Int)] {
        var edgePixels: [(x: Int, y: Int)] = []
        edgePixels.reserveCapacity(2 * (width + height) - 4)
        for x in 0 ..< width {
            edgePixels.append((x, 0))
            if height > 1 {
                edgePixels.append((x, height - 1))
            }
        }
        for y in 1 ..< (height - 1) {
            edgePixels.append((0, y))
            if width > 1 {
                edgePixels.append((width - 1, y))
            }
        }
        return edgePixels
    }

    /// Returns a copy that owns its own pixel buffer.
    ///
    /// cropping(to:) returns an image sharing the parent's data provider, so a
    /// small cached crop pins the entire multi-MB composite it was cut from.
    /// Redrawing into a fresh bitmap context detaches it.
    nonisolated func detachedCopy() -> CGImage {
        guard width > 0, height > 0 else { return self }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return self
        }
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? self
    }

    /// Whether no pixel in the image rises above the given alpha threshold.
    ///
    /// Reads alpha bytes straight from the data provider for 32-bit images
    /// with a known byte order; other formats fall back to AlphaMask.
    ///
    /// - Parameter alphaThreshold: The alpha value at or below which a pixel is
    ///   treated as fully see-through.
    nonisolated func isTransparent(alphaThreshold: CGFloat = 0) -> Bool {
        guard width > 0, height > 0 else { return true }
        guard alphaThreshold < 1 else { return false }

        let bytesPerPixel = bitsPerPixel / 8

        guard bytesPerPixel == 4 else {
            return isTransparentSlow(alphaThreshold: alphaThreshold)
        }

        // No alpha channel, image is fully opaque.
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        case .premultipliedFirst, .first, .premultipliedLast, .last, .alphaOnly:
            break
        @unknown default:
            return isTransparentSlow(alphaThreshold: alphaThreshold)
        }

        // Screen captures are usually byteOrder32Little + premultipliedFirst,
        // stored as BGRA (alpha at byte 3).
        let byteOrder = CGBitmapInfo(rawValue: bitmapInfo.rawValue).intersection(.byteOrderMask)

        let isLittleEndian: Bool
        switch byteOrder {
        case .byteOrder32Little:
            isLittleEndian = true
        case .byteOrder32Big:
            isLittleEndian = false
        default:
            // byteOrderDefault or 16-bit orders, fall back for safety.
            return isTransparentSlow(alphaThreshold: alphaThreshold)
        }

        let alphaOffset: Int
        switch (alphaInfo, isLittleEndian) {
        case (.premultipliedFirst, true), (.first, true):
            alphaOffset = 3 // Logical ARGB stored as BGRA
        case (.premultipliedLast, true), (.last, true):
            alphaOffset = 0 // Logical RGBA stored as ABGR
        case (.premultipliedFirst, false), (.first, false):
            alphaOffset = 0 // Big-endian: ARGB as-is
        case (.premultipliedLast, false), (.last, false):
            alphaOffset = 3 // Big-endian: RGBA as-is
        default:
            // .alphaOnly is excluded by the bytesPerPixel == 4 guard above.
            return isTransparentSlow(alphaThreshold: alphaThreshold)
        }

        // Keeps cfData, and so the byte pointer, alive for the whole scan.
        guard let cfData = dataProvider?.data,
              let dataPointer = CFDataGetBytePtr(cfData)
        else {
            return isTransparentSlow(alphaThreshold: alphaThreshold)
        }

        return withExtendedLifetime(cfData) {
            // A buffer too short for the scan falls back to the slow path.
            guard let alphaView = AlphaChannelView(
                bytes: UnsafeRawBufferPointer(start: dataPointer, count: CFDataGetLength(cfData)),
                width: width,
                height: height,
                rowStride: bytesPerRow,
                pixelStride: bytesPerPixel,
                alphaOffset: alphaOffset,
                alphaThreshold: alphaThreshold
            ) else {
                return isTransparentSlow(alphaThreshold: alphaThreshold)
            }
            return alphaView.isTransparent()
        }
    }

    /// Draws the image into a premultiplied RGBA8 scratch bitmap and hands
    /// its bytes to body, with the row stride. false when the image has no
    /// area or the bitmap cannot be made.
    ///
    /// The bitmap memory is only valid inside body: a context keeps using
    /// the buffer it was given, so an escaping &array argument must not be
    /// what it gets.
    private nonisolated func withPremultipliedRGBA8(
        _ body: (UnsafeBufferPointer<UInt8>, Int) -> Bool
    ) -> Bool {
        guard width > 0, height > 0 else { return false }
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        return pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress, let context = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
            return body(UnsafeBufferPointer(buffer.bindMemory(to: UInt8.self)), bytesPerRow)
        }
    }

    /// Whether the crop's outermost ring of pixels is (near) fully opaque.
    ///
    /// Tells a window's transparent background from an opaque slab. Drawn
    /// through an alpha context so an image without alpha reads opaque.
    ///
    /// - Parameter minimumOpaqueShare: Share of ring pixels that must be
    ///   opaque, loose enough that an anti-aliased glyph edge touching the
    ///   ring does not flip it.
    nonisolated func hasOpaquePerimeter(minimumOpaqueShare: Double = 0.95) -> Bool {
        withPremultipliedRGBA8 { bytes, bytesPerRow -> Bool in
            let bytesPerPixel = 4
            var ringPixels = 0
            var opaquePixels = 0
            func visit(x: Int, y: Int) {
                ringPixels += 1
                if bytes[y * bytesPerRow + x * bytesPerPixel + 3] > 250 {
                    opaquePixels += 1
                }
            }
            for x in 0 ..< width {
                visit(x: x, y: 0)
                if height > 1 {
                    visit(x: x, y: height - 1)
                }
            }
            if height > 2 {
                for y in 1 ..< height - 1 {
                    visit(x: 0, y: y)
                    if width > 1 {
                        visit(x: width - 1, y: y)
                    }
                }
            }
            guard ringPixels > 0 else { return false }
            return Double(opaquePixels) / Double(ringPixels) >= minimumOpaqueShare
        }
    }

    /// Whether the image is a single-ink glyph, one grey ink on
    /// transparency, rather than a colour icon.
    ///
    /// A single-ink crop can be re-inked as a mask; colour icons must keep
    /// their pixels. Tests the share of vivid pixels rather than all-grey,
    /// because a thin glyph's tinted anti-aliased fringe can be half its pixels.
    ///
    /// - Parameters:
    ///   - vividChroma: Channel spread, in 0...1, above which a pixel counts
    ///     as vivid colour rather than a tinted edge.
    ///   - maximumVividShare: Share of visible pixels allowed to be vivid.
    nonisolated func isSingleInkGlyph(
        vividChroma: Double = 0.3,
        maximumVividShare: Double = 0.02
    ) -> Bool {
        withPremultipliedRGBA8 { bytes, _ -> Bool in
            let bytesPerPixel = 4
            var visible = 0
            var opaque = 0
            var vivid = 0
            for offset in stride(from: 0, to: bytes.count, by: bytesPerPixel) {
                let alpha = Double(bytes[offset + 3]) / 255
                // Faint edge pixels carry too little colour to judge.
                guard alpha >= 0.5 else { continue }
                visible += 1
                if alpha > 0.98 {
                    opaque += 1
                }
                let red = Double(bytes[offset]) / 255 / alpha
                let green = Double(bytes[offset + 1]) / 255 / alpha
                let blue = Double(bytes[offset + 2]) / 255 / alpha
                if max(red, green, blue) - min(red, green, blue) > vividChroma {
                    vivid += 1
                }
            }
            // Nothing to judge, or an opaque tile (an unknocked background)
            // rather than a glyph on transparency.
            guard visible > 0, Double(opaque) / Double(width * height) < 0.9 else {
                return false
            }
            return Double(vivid) / Double(visible) <= maximumVividShare
        }
    }

    /// Slow path for isTransparent using AlphaMask.
    private nonisolated func isTransparentSlow(alphaThreshold: CGFloat) -> Bool {
        AlphaMask(of: self, alphaThreshold: alphaThreshold)?.isTransparent() ?? false
    }

    // MARK: Palette Derivation

    /// Returns the image's dominant colors, most-covering first.
    ///
    /// Samples coarsely for WallpaperPalette.derive. The grid is larger than
    /// averageColor's 10×10 so a small subject survives bucketing.
    ///
    /// - Parameters:
    ///   - maximumCount: The most colors to return.
    ///   - alphaThreshold: Pixels whose alpha falls below this are ignored.
    nonisolated func dominantColors(maximumCount: Int = 5, alphaThreshold: CGFloat = 0.5) -> WallpaperPalette {
        let sampleWidth = min(width, 48)
        let sampleHeight = min(height, 48)
        guard let pixels = downsampledPixels(width: sampleWidth, height: sampleHeight, in: averagingColorSpace(preferring: nil)) else {
            return WallpaperPalette(swatches: [])
        }

        let minimumAlpha = UInt64((alphaThreshold.clamped(to: 0 ... 1) * 255).rounded(.up))
        var samples = [WallpaperPalette.Sample]()
        samples.reserveCapacity(pixels.count)
        for pixel in pixels {
            let (alpha, red, green, blue) = Self.unpackARGB(pixel)
            guard alpha >= minimumAlpha else { continue }
            samples.append(WallpaperPalette.Sample(
                red: Double(red) / 255,
                green: Double(green) / 255,
                blue: Double(blue) / 255
            ))
        }
        return WallpaperPalette.derive(from: samples, maximumCount: maximumCount)
    }
}
