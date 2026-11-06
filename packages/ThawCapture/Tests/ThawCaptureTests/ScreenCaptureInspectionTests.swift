//
//  ScreenCaptureInspectionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import ThawCapture

@Suite("Capture inspection geometry")
struct ScreenCaptureInspectionTests {
    /// A 1470×40pt strip captured on a 2× display.
    private let stripFrame = CGRect(x: 0, y: 0, width: 1470, height: 40)
    private let stripImageBounds = CGRect(x: 0, y: 0, width: 2940, height: 80)

    @Test
    func anItemMapsIntoTheStripAtPixelScale() {
        let mapping = ScreenCapture.cropMapping(
            itemBounds: CGRect(x: 1362, y: 0, width: 24, height: 24),
            captureFrame: stripFrame,
            scale: 2,
            imageBounds: stripImageBounds
        )

        #expect(mapping?.raw == CGRect(x: 2724, y: 0, width: 48, height: 48))
        #expect(mapping?.clamped == CGRect(x: 2724, y: 0, width: 48, height: 48))
        #expect(mapping?.isComplete == true)
    }

    /// The mapping is a translation plus a scale, with no axis flip: both frames
    /// are Y-down and CGImage rows run top-down. A flip here would put every
    /// crop on the wrong half of the strip.
    @Test
    func theCaptureOriginIsSubtractedBeforeScaling() {
        let secondDisplayStrip = CGRect(x: 1470, y: 0, width: 1920, height: 40)
        let mapping = ScreenCapture.cropMapping(
            itemBounds: CGRect(x: 1500, y: 4, width: 20, height: 22),
            captureFrame: secondDisplayStrip,
            scale: 2,
            imageBounds: CGRect(x: 0, y: 0, width: 3840, height: 80)
        )

        #expect(mapping?.raw == CGRect(x: 60, y: 8, width: 40, height: 44))
        #expect(mapping?.isComplete == true)
    }

    /// Rounding outward is what keeps a sub-pixel origin from shaving a column
    /// off the glyph, so the expected rect must fully contain the raw one.
    @Test
    func subPixelBoundsRoundOutwardRatherThanNearest() throws {
        let mapping = try #require(
            ScreenCapture.cropMapping(
                itemBounds: CGRect(x: 100.3, y: 0, width: 24.4, height: 22),
                captureFrame: stripFrame,
                scale: 2,
                imageBounds: stripImageBounds
            )
        )

        #expect(mapping.raw == CGRect(x: 200.6, y: 0, width: 48.8, height: 44))
        #expect(mapping.expected == CGRect(x: 200, y: 0, width: 50, height: 44))
        #expect(mapping.expected.contains(mapping.raw))
        #expect(mapping.isComplete)
    }

    @Test
    func aScaleOfOneLeavesTheGeometryInPoints() {
        let mapping = ScreenCapture.cropMapping(
            itemBounds: CGRect(x: 12, y: 2, width: 24, height: 24),
            captureFrame: stripFrame,
            scale: 1,
            imageBounds: CGRect(x: 0, y: 0, width: 1470, height: 40)
        )

        #expect(mapping?.clamped == CGRect(x: 12, y: 2, width: 24, height: 24))
        #expect(mapping?.isComplete == true)
    }

    /// An item overhanging the frame yields a sliver, which is not its glyph.
    @Test
    func anItemOverhangingTheFrameIsIncomplete() throws {
        let mapping = try #require(
            ScreenCapture.cropMapping(
                itemBounds: CGRect(x: 1450, y: 0, width: 40, height: 24),
                captureFrame: stripFrame,
                scale: 2,
                imageBounds: stripImageBounds
            )
        )

        #expect(mapping.expected == CGRect(x: 2900, y: 0, width: 80, height: 48))
        #expect(mapping.clamped == CGRect(x: 2900, y: 0, width: 40, height: 48))
        #expect(!mapping.isComplete)
    }

    /// macOS 27 parks concealed items far below the bar (y ≈ 1428). Those bounds
    /// map entirely outside the strip, and must not read as a usable crop.
    @Test
    func parkedBoundsFallOutsideTheFrameEntirely() throws {
        let mapping = try #require(
            ScreenCapture.cropMapping(
                itemBounds: CGRect(x: 600, y: 1428, width: 24, height: 24),
                captureFrame: stripFrame,
                scale: 2,
                imageBounds: stripImageBounds
            )
        )

        #expect(mapping.clamped.isNull)
        #expect(!mapping.isComplete)
    }

    /// Whole-pixel rounding can push an edge item one pixel past the image;
    /// forgiving that is what stops edge glyphs falling back to their app icon.
    @Test
    func aSinglePixelOfClampingIsForgiven() {
        #expect(
            ScreenCapture.isCompleteCrop(
                expected: CGRect(x: 2892, y: 0, width: 48, height: 48),
                clamped: CGRect(x: 2892, y: 0, width: 47, height: 48)
            )
        )
        #expect(
            !ScreenCapture.isCompleteCrop(
                expected: CGRect(x: 2892, y: 0, width: 48, height: 48),
                clamped: CGRect(x: 2892, y: 0, width: 44, height: 48)
            )
        )
    }

    @Test
    func degenerateGeometryHasNoMapping() {
        #expect(
            ScreenCapture.cropMapping(
                itemBounds: CGRect(x: 12, y: 0, width: 24, height: 24),
                captureFrame: stripFrame,
                scale: 0,
                imageBounds: stripImageBounds
            ) == nil
        )
        #expect(
            ScreenCapture.cropMapping(
                itemBounds: .zero,
                captureFrame: stripFrame,
                scale: 2,
                imageBounds: stripImageBounds
            ) == nil
        )
        #expect(
            ScreenCapture.cropMapping(
                itemBounds: CGRect(x: 12, y: 0, width: 24, height: 24),
                captureFrame: stripFrame,
                scale: 2,
                imageBounds: .null
            ) == nil
        )
    }

    /// The inspector overlay calls the wrapper, so it must match the free
    /// function the pipeline uses.
    @Test
    func theCaptureWrapperAgreesWithTheFreeFunction() throws {
        let image = try #require(makeTestImage(width: 2940, height: 80))
        let capture = ScreenCapture.MenuBarHostingCapture(
            image: image,
            windowFrame: stripFrame,
            scale: 2
        )
        let itemBounds = CGRect(x: 1362, y: 0, width: 24, height: 24)

        #expect(capture.imageBounds == stripImageBounds)
        #expect(
            capture.cropMapping(forItemBounds: itemBounds) == ScreenCapture.cropMapping(
                itemBounds: itemBounds,
                captureFrame: stripFrame,
                scale: 2,
                imageBounds: stripImageBounds
            )
        )
    }

    /// The mapping is exact for any capture frame, not only a display strip:
    /// raw is the pipeline's own unrounded arithmetic.
    @Test
    func cropMappingIsExactForAnArbitraryCaptureFrame() throws {
        let first = CGRect(x: 1200, y: 0, width: 24, height: 24)
        let second = CGRect(x: 1240, y: 0, width: 30, height: 24)
        let boundsUnion = first.union(second)
        let scale: CGFloat = 2

        let mapping = try #require(
            ScreenCapture.cropMapping(
                itemBounds: second,
                captureFrame: boundsUnion,
                scale: scale,
                imageBounds: ScreenCapture.imageBounds(
                    ofWidth: Int(boundsUnion.width * scale),
                    height: Int(boundsUnion.height * scale)
                )
            )
        )

        // Exactly what the pipeline computes for this item.
        let pipelineCropRect = CGRect(
            x: (second.origin.x - boundsUnion.origin.x) * scale,
            y: (second.origin.y - boundsUnion.origin.y) * scale,
            width: second.width * scale,
            height: second.height * scale
        )

        #expect(mapping.raw == pipelineCropRect)
        #expect(mapping.clamped == pipelineCropRect)
        #expect(mapping.isComplete)
    }

    /// The scope shown to the user is read from the same function the capture
    /// configures itself with, so the two cannot disagree.
    @Test
    func theInspectableScopeIsTheCapturedScope() {
        let displayFrame = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let scope = ScreenCapture.inspectableStripFrame(displayFrame: displayFrame)

        #expect(scope == ScreenCapture.menuBarDisplayStripFrame(displayFrame: displayFrame))
        #expect(scope == CGRect(x: 0, y: 0, width: 1470, height: 40))

        let tall = ScreenCapture.inspectableStripFrame(displayFrame: displayFrame, menuBarHeight: 49)
        #expect(tall == ScreenCapture.menuBarDisplayStripFrame(
            displayFrame: displayFrame,
            height: ScreenCapture.menuBarDisplayStripHeight(menuBarHeight: 49)
        ))
        #expect(tall.height == 49)
    }

    private func makeTestImage(width: Int, height: Int) -> CGImage? {
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        return context.makeImage()
    }
}
