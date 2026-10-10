//
//  MenuBarItemCropBoundsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// Characterization for isCropWithinItemBounds and hasOpaquePerimeter: a crop
/// may exceed the item's frame only by the rounding tolerance; an opaque ring means it is not the item.
@Suite("Glyph crop bounds")
struct MenuBarItemCropBoundsTests {
    private static let itemBounds = CGRect(x: 0, y: 0, width: 20, height: 20)

    @Test("a crop that fits the item's frame is accepted")
    func cropInsideBoundsAccepted() {
        #expect(
            MenuBarItemImageCache.isCropWithinItemBounds(
                imageWidth: 40, imageHeight: 40, itemBounds: Self.itemBounds, scale: 2
            )
        )
        // The tolerance allows exactly two points of outward rounding.
        #expect(
            MenuBarItemImageCache.isCropWithinItemBounds(
                imageWidth: 44, imageHeight: 44, itemBounds: Self.itemBounds, scale: 2
            )
        )
        #expect(
            MenuBarItemImageCache.isCropWithinItemBounds(
                imageWidth: 22, imageHeight: 22, itemBounds: Self.itemBounds, scale: 1
            )
        )
    }

    @Test("a crop one pixel past the tolerance is rejected")
    func cropPastToleranceRejected() {
        #expect(
            !MenuBarItemImageCache.isCropWithinItemBounds(
                imageWidth: 45, imageHeight: 40, itemBounds: Self.itemBounds, scale: 2
            )
        )
        #expect(
            !MenuBarItemImageCache.isCropWithinItemBounds(
                imageWidth: 23, imageHeight: 22, itemBounds: Self.itemBounds, scale: 1
            )
        )
        #expect(
            !MenuBarItemImageCache.isCropWithinItemBounds(
                imageWidth: 40, imageHeight: 45, itemBounds: Self.itemBounds, scale: 2
            )
        )
    }

    @Test("a crop carrying a neighbouring item's glyph is rejected")
    func neighbourGlyphRejected() {
        #expect(
            !MenuBarItemImageCache.isCropWithinItemBounds(
                imageWidth: 200, imageHeight: 40, itemBounds: Self.itemBounds, scale: 2
            )
        )
    }

    @Test("a wider tolerance accepts a crop the default rejects")
    func toleranceWidensBounds() {
        #expect(
            !MenuBarItemImageCache.isCropWithinItemBounds(
                imageWidth: 52, imageHeight: 40, itemBounds: Self.itemBounds, scale: 2
            )
        )
        #expect(
            MenuBarItemImageCache.isCropWithinItemBounds(
                imageWidth: 52, imageHeight: 40, itemBounds: Self.itemBounds, scale: 2, tolerancePoints: 6
            )
        )
    }

    @Test("unusable item bounds are rejected")
    func unusableBoundsRejected() {
        #expect(
            !MenuBarItemImageCache.isCropWithinItemBounds(
                imageWidth: 40, imageHeight: 40, itemBounds: .null, scale: 2
            )
        )
        #expect(
            !MenuBarItemImageCache.isCropWithinItemBounds(
                imageWidth: 40, imageHeight: 40, itemBounds: .zero, scale: 2
            )
        )
        #expect(
            !MenuBarItemImageCache.isCropWithinItemBounds(
                imageWidth: 40, imageHeight: 40,
                itemBounds: CGRect(x: 0, y: 0, width: 0, height: 20), scale: 2
            )
        )
        #expect(
            !MenuBarItemImageCache.isCropWithinItemBounds(
                imageWidth: 40, imageHeight: 40,
                itemBounds: CGRect(x: 0, y: 0, width: 20, height: 0), scale: 2
            )
        )
    }

    @Test("an unusable scale is rejected")
    func unusableScaleRejected() {
        #expect(
            !MenuBarItemImageCache.isCropWithinItemBounds(
                imageWidth: 40, imageHeight: 40, itemBounds: Self.itemBounds, scale: 0
            )
        )
        #expect(
            !MenuBarItemImageCache.isCropWithinItemBounds(
                imageWidth: 40, imageHeight: 40, itemBounds: Self.itemBounds, scale: -2
            )
        )
        #expect(
            !MenuBarItemImageCache.isCropWithinItemBounds(
                imageWidth: 40, imageHeight: 40, itemBounds: Self.itemBounds, scale: .infinity
            )
        )
    }
}

/// Characterization for the coverage-based overflow rejection: the chevron sits
/// mid-control, so a neighbour grazing the frame's edge is not contamination.
@Suite("Native overflow contamination")
struct NativeOverflowContaminationTests {
    private let chevron = CGRect(x: 850, y: 0, width: 24, height: 24)

    @Test("a crop spanning the chevron is contaminated")
    func cropSpanningChevronContaminated() {
        #expect(
            MenuBarItemImageCache.isContaminatedByNativeOverflow(
                CGRect(x: 840, y: 0, width: 40, height: 24),
                overflowBounds: [chevron]
            )
        )
    }

    @Test("a one-point graze is not contamination")
    func grazeIsNotContamination() {
        #expect(
            !MenuBarItemImageCache.isContaminatedByNativeOverflow(
                CGRect(x: 836, y: 0, width: 15, height: 24),
                overflowBounds: [chevron]
            )
        )
    }

    @Test("a disjoint frame is not contaminated")
    func disjointFrameNotContaminated() {
        #expect(
            !MenuBarItemImageCache.isContaminatedByNativeOverflow(
                CGRect(x: 700, y: 0, width: 24, height: 24),
                overflowBounds: [chevron]
            )
        )
    }

    @Test("an item on another display's bar lies on a menu bar; a parked one does not")
    func otherDisplaysBarVersusParked() {
        let displays = [CGRect(x: 0, y: 0, width: 1728, height: 1117), CGRect(x: -113, y: -1080, width: 1920, height: 1080)]
        #expect(MenuBarItemImageCache.liesOnAMenuBar(
            CGRect(x: 1390, y: -1076.5, width: 57, height: 24), barHeight: 40, displayBounds: displays
        ))
        #expect(!MenuBarItemImageCache.liesOnAMenuBar(
            CGRect(x: 900, y: 1428, width: 24, height: 24), barHeight: 40, displayBounds: displays
        ))
    }

    @Test("the coverage threshold is honored")
    func coverageThresholdHonored() {
        // 9 of 24 points: below the default half-control coverage...
        #expect(
            !MenuBarItemImageCache.isContaminatedByNativeOverflow(
                CGRect(x: 841, y: 0, width: 18, height: 24),
                overflowBounds: [chevron]
            )
        )
        // ...and above a quarter-control threshold.
        #expect(
            MenuBarItemImageCache.isContaminatedByNativeOverflow(
                CGRect(x: 841, y: 0, width: 18, height: 24),
                overflowBounds: [chevron],
                minimumOverflowCoverage: 0.25
            )
        )
    }
}

/// Characterization for the parked/phantom skip: a frame another item occupies,
/// or one parked off the band, is not capture geometry.
@Suite("Unusable capture geometry")
struct UnusableCaptureGeometryTests {
    private func item(
        _ title: String,
        x: CGFloat,
        windowID: UInt32,
        y: CGFloat = 4,
        width: CGFloat = 24
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(
                namespace: .string("com.example.\(title)"),
                title: title,
                instanceIndex: 0
            ),
            windowID: windowID,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: y, width: width, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    /// The observed macOS 27 stack: a row of concealed items parked at one
    /// x. Every stacked frame is unusable.
    @Test("a parked stack at one x is unusable")
    func parkedStackIsUnusable() {
        let a = item("Alfred", x: 852, windowID: 1)
        let b = item("DockDoor", x: 852, windowID: 2)
        let c = item("LinkLiar", x: 852.2, windowID: 3)
        let peers = [a, b, c]

        #expect(MenuBarItemImageCache.hasUnusableCaptureGeometry(a, among: peers))
        #expect(MenuBarItemImageCache.hasUnusableCaptureGeometry(b, among: peers))
        #expect(MenuBarItemImageCache.hasUnusableCaptureGeometry(c, among: peers))
    }

    @Test("an item half-covering a neighbour is unusable")
    func halfCoveredNeighbourUnusable() {
        // 15 of the narrow item's 20 points: past the half-frame threshold
        // hasPhantomFrame requires (strictly more than half, not equal).
        let narrow = item("narrow", x: 850, windowID: 1, width: 20)
        let wide = item("wide", x: 855, windowID: 2, width: 40)
        let peers = [narrow, wide]

        #expect(MenuBarItemImageCache.hasUnusableCaptureGeometry(narrow, among: peers))
        #expect(MenuBarItemImageCache.hasUnusableCaptureGeometry(wide, among: peers))
    }

    @Test("healthy distinct frames are usable")
    func healthyFramesUsable() {
        let a = item("Alfred", x: 800, windowID: 1)
        let b = item("DockDoor", x: 830, windowID: 2, width: 36)
        let peers = [a, b]

        #expect(!MenuBarItemImageCache.hasUnusableCaptureGeometry(a, among: peers))
        #expect(!MenuBarItemImageCache.hasUnusableCaptureGeometry(b, among: peers))
    }

    /// Assertion-reflow collateral parks at y≈1400 while the bar reshuffles;
    /// its frame is not on the bar band.
    @Test("a frame parked off the bar band is unusable")
    func offBandFrameUnusable() {
        let onBar = item("Alfred", x: 800, windowID: 1)
        let parked = item("DockDoor", x: 830, windowID: 2, y: 1400)
        let peers = [onBar, parked]

        #expect(MenuBarItemImageCache.hasUnusableCaptureGeometry(parked, among: peers))
        #expect(!MenuBarItemImageCache.hasUnusableCaptureGeometry(onBar, among: peers))
    }

    @Test("a degenerate frame is unusable")
    func degenerateFrameUnusable() {
        let healthy = item("Alfred", x: 800, windowID: 1)
        let sliver = item("ghost", x: 830, windowID: 2, width: 0)
        let peers = [healthy, sliver]

        #expect(MenuBarItemImageCache.hasUnusableCaptureGeometry(sliver, among: peers))
    }
}

/// Characterization for the opaque-border rejection: the bar window a crop falls
/// back to is a solid slab, so an opaque ring means the crop is bar chrome.
@Suite("Opaque perimeter")
struct MenuBarItemOpaquePerimeterTests {
    @Test("a solid opaque bitmap has an opaque perimeter")
    func solidOpaquePerimeter() {
        #expect(Self.bitmap(width: 4, height: 4, opaqueColumns: 4).hasOpaquePerimeter())
    }

    @Test("a transparent bitmap has no opaque perimeter")
    func transparentPerimeter() {
        #expect(!Self.bitmap(width: 4, height: 4, opaqueColumns: 0).hasOpaquePerimeter())
    }

    @Test("a half-opaque bitmap has no opaque perimeter")
    func halfOpaquePerimeter() {
        #expect(!Self.bitmap(width: 4, height: 4, opaqueColumns: 2).hasOpaquePerimeter())
    }

    private static func bitmap(width: Int, height: Int, opaqueColumns: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        if opaqueColumns > 0 {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: opaqueColumns, height: height))
        }
        return context.makeImage()!
    }
}
