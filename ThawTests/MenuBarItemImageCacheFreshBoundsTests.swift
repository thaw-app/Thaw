//
//  MenuBarItemImageCacheFreshBoundsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class MenuBarItemImageCacheFreshBoundsTests: XCTestCase {
    private let cachedBounds = CGRect(x: 100, y: 0, width: 24, height: 22)
    private let liveBounds = CGRect(x: 200, y: 0, width: 24, height: 22)

    func testCachedBoundsAreUsedWhenFreshBoundsAreDisabled() {
        let item = makeItem()

        let captures = MenuBarItemImageCache.captureBounds(
            for: [item],
            freshBounds: false,
            liveBoundsByID: [item.uniqueIdentifier: liveBounds],
            screenFrame: nil
        )

        XCTAssertEqual(captures.first?.bounds, cachedBounds)
    }

    func testLiveBoundsAreUsedWhenFreshBoundsAreEnabled() {
        let item = makeItem()

        let captures = MenuBarItemImageCache.captureBounds(
            for: [item],
            freshBounds: true,
            liveBoundsByID: [item.uniqueIdentifier: liveBounds],
            screenFrame: nil
        )

        XCTAssertEqual(captures.first?.bounds, liveBounds)
    }

    func testVisibleCaptureUsesCacheCycleBounds() {
        let item = makeItem()
        let useFreshBounds = MenuBarItemImageCache.shouldUseFreshBounds(
            for: .visible,
            revealedSection: nil
        )

        let captures = MenuBarItemImageCache.captureBounds(
            for: [item],
            freshBounds: useFreshBounds,
            liveBoundsByID: [item.uniqueIdentifier: liveBounds],
            screenFrame: nil
        )

        XCTAssertFalse(useFreshBounds)
        XCTAssertEqual(captures.first?.bounds, cachedBounds)
        XCTAssertNotEqual(captures.first?.bounds, liveBounds)
    }

    func testRevealedConcealedCaptureUsesFreshBounds() {
        XCTAssertTrue(
            MenuBarItemImageCache.shouldUseFreshBounds(
                for: .hidden,
                revealedSection: .hidden
            )
        )
        XCTAssertTrue(
            MenuBarItemImageCache.shouldUseFreshBounds(
                for: .hidden,
                revealedSection: .alwaysHidden
            )
        )
        XCTAssertTrue(
            MenuBarItemImageCache.shouldUseFreshBounds(
                for: .alwaysHidden,
                revealedSection: .alwaysHidden
            )
        )
    }

    func testLittleSnitchResolvedItemIsExcludedFromCapture() {
        let item = makeItem(
            tag: .appItem(bundleID: "at.obdev.littlesnitch.agent", title: "Item-0")
        )

        XCTAssertTrue(
            MenuBarItemImageCache.shouldExcludeOpaqueStatusItemFromCapture(
                item,
                littleSnitchRunning: true
            )
        )
    }

    func testLittleSnitchUnresolvedMenuBarAgentSlotIsExcludedFromCapture() {
        let item = makeItem(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "Item-0")
        )

        XCTAssertTrue(
            MenuBarItemImageCache.shouldExcludeOpaqueStatusItemFromCapture(
                item,
                littleSnitchRunning: true
            )
        )
    }

    func testGenericMenuBarAgentSlotRemainsCapturableWithoutLittleSnitch() {
        let item = makeItem(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "Item-0")
        )

        XCTAssertFalse(
            MenuBarItemImageCache.shouldExcludeOpaqueStatusItemFromCapture(
                item,
                littleSnitchRunning: false
            )
        )
    }

    func testOpaqueIdentitiesAreRemovedFromEveryCaptureRequest() {
        let resolved = makeItem(
            tag: .appItem(bundleID: "at.obdev.littlesnitch.agent", title: "Item-0")
        )
        let unresolved = makeItem(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "Item-0")
        )
        let neighbor = makeItem(
            tag: .appItem(bundleID: "com.test.neighbor", title: "Neighbor")
        )

        let capturable = MenuBarItemImageCache.excludingOpaqueStatusItems(
            [resolved, unresolved, neighbor],
            littleSnitchRunning: true
        )

        XCTAssertEqual(capturable.map(\.tag), [neighbor.tag])
    }

    func testCropsIntersectingLittleSnitchOpaqueSlotAreExcluded() {
        let left = makeItem(
            tag: .appItem(bundleID: "com.test.left", title: "Left"),
            bounds: CGRect(x: 100, y: 0, width: 30, height: 22)
        )
        let contaminated = makeItem(
            tag: .appItem(bundleID: "com.test.contaminated", title: "Contaminated"),
            bounds: CGRect(x: 125, y: 0, width: 30, height: 22)
        )
        let right = makeItem(
            tag: .appItem(bundleID: "com.test.right", title: "Right"),
            bounds: CGRect(x: 170, y: 0, width: 30, height: 22)
        )

        let captures = MenuBarItemImageCache.excludingOpaqueCaptureBounds(
            [
                (item: left, bounds: left.bounds),
                (item: contaminated, bounds: contaminated.bounds),
                (item: right, bounds: right.bounds),
            ],
            opaqueBounds: [CGRect(x: 130, y: 0, width: 40, height: 22)]
        )

        XCTAssertEqual(captures.map(\.item.tag), [left.tag, right.tag])
    }

    func testVerticallyArrangedDisplayDoesNotRejectCGCoordinates() {
        let item = makeItem(bounds: CGRect(x: 200, y: -40, width: 24, height: 22))

        let captures = MenuBarItemImageCache.captureBounds(
            for: [item],
            freshBounds: false,
            liveBoundsByID: [:],
            screenFrame: CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        )

        XCTAssertEqual(captures.count, 1)
    }

    func testBoundsOutsideDisplayHorizontalRangeAreRejected() {
        let item = makeItem(bounds: CGRect(x: -200, y: 0, width: 24, height: 22))

        let captures = MenuBarItemImageCache.captureBounds(
            for: [item],
            freshBounds: false,
            liveBoundsByID: [:],
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        XCTAssertTrue(captures.isEmpty)
    }

    @available(macOS 27, *)
    func testCompleteCropAllowsOnePixelIntegralRoundingAtImageEdge() {
        XCTAssertTrue(
            MenuBarItemImageCache.isCompleteCrop(
                expected: CGRect(x: -1, y: 0, width: 25, height: 22),
                clamped: CGRect(x: 0, y: 0, width: 24, height: 22)
            )
        )
    }

    @available(macOS 27, *)
    func testCompleteCropRejectsTruncatedHostingWindowFrame() {
        XCTAssertFalse(
            MenuBarItemImageCache.isCompleteCrop(
                expected: CGRect(x: -6, y: 0, width: 30, height: 22),
                clamped: CGRect(x: 0, y: 0, width: 24, height: 22)
            )
        )
    }

    @available(macOS 27, *)
    func testCompleteCropRejectsMissingVerticalContent() {
        XCTAssertFalse(
            MenuBarItemImageCache.isCompleteCrop(
                expected: CGRect(x: 0, y: 0, width: 24, height: 22),
                clamped: CGRect(x: 0, y: 0, width: 24, height: 17)
            )
        )
    }

    @available(macOS 27, *)
    func testCropRectOwnerIdentifiesDuplicateCaptureCandidates() {
        let cropRect = CGRect(x: 100, y: 0, width: 24, height: 22)
        let tag = MenuBarItemTag.appItem(bundleID: "com.test.capture", title: "Capture")

        XCTAssertNil(
            MenuBarItemImageCache.cropRectOwner(
                cropRect,
                cropRectOwners: [:]
            )
        )
        XCTAssertEqual(
            MenuBarItemImageCache.cropRectOwner(
                cropRect,
                cropRectOwners: [cropRect: tag]
            ),
            tag
        )
    }

    @available(macOS 27, *)
    func testCropOwnershipUsesActualClampedPixelRect() {
        let imageBounds = CGRect(x: 0, y: 0, width: 200, height: 60)
        let firstExpected = CGRect(x: -1, y: 0, width: 25, height: 44)
        let secondExpected = CGRect(x: 0, y: 0, width: 24, height: 44)
        let firstTag = MenuBarItemTag.appItem(bundleID: "com.test.first", title: "First")

        let firstActual = MenuBarItemImageCache.captureCropRect(
            expected: firstExpected,
            imageBounds: imageBounds
        )
        let secondActual = MenuBarItemImageCache.captureCropRect(
            expected: secondExpected,
            imageBounds: imageBounds
        )

        XCTAssertEqual(firstActual, secondActual)
        XCTAssertEqual(
            MenuBarItemImageCache.cropRectOwner(
                secondActual,
                cropRectOwners: [firstActual: firstTag]
            ),
            firstTag
        )
    }

    @available(macOS 27, *)
    func testCaptureBoundsIntersectingNativeOverflowAreContaminated() {
        let overflowBounds = [CGRect(x: 1180, y: 0, width: 24, height: 30)]

        XCTAssertTrue(
            MenuBarItemImageCache.isContaminatedByNativeOverflow(
                CGRect(x: 1182, y: 3, width: 20, height: 24),
                overflowBounds: overflowBounds
            )
        )
        XCTAssertFalse(
            MenuBarItemImageCache.isContaminatedByNativeOverflow(
                CGRect(x: 1150, y: 3, width: 24, height: 24),
                overflowBounds: overflowBounds
            )
        )
    }

    @available(macOS 27, *)
    func testPlausibleHostingCaptureAcceptsMatchingPixelSize() {
        XCTAssertTrue(
            MenuBarItemImageCache.isPlausibleHostingCapture(
                imageWidth: 2560,
                imageHeight: 60,
                windowFrame: CGRect(x: 0, y: 0, width: 1280, height: 30),
                scale: 2
            )
        )
    }

    @available(macOS 27, *)
    func testPlausibleHostingCaptureRejectsScaleMismatch() {
        // 3840×30 image for a 3840×30pt window at reported scale 2 is impossible.
        XCTAssertFalse(
            MenuBarItemImageCache.isPlausibleHostingCapture(
                imageWidth: 3840,
                imageHeight: 30,
                windowFrame: CGRect(x: 0, y: 0, width: 3840, height: 30),
                scale: 2
            )
        )
    }

    @available(macOS 27, *)
    func testPlausibleItemCaptureBoundsRejectsNearFullBarFrame() {
        let window = CGRect(x: 0, y: 0, width: 1280, height: 30)
        XCTAssertFalse(
            MenuBarItemImageCache.isPlausibleItemCaptureBounds(
                CGRect(x: 0, y: 3, width: 900, height: 24),
                windowFrame: window
            )
        )
        XCTAssertTrue(
            MenuBarItemImageCache.isPlausibleItemCaptureBounds(
                CGRect(x: 1100, y: 3, width: 24, height: 24),
                windowFrame: window
            )
        )
        // Formerly allowed via 0.35 × window width; must stay rejected.
        XCTAssertFalse(
            MenuBarItemImageCache.isPlausibleItemCaptureBounds(
                CGRect(x: 100, y: 3, width: 400, height: 24),
                windowFrame: window
            )
        )
    }

    @available(macOS 27, *)
    func testStatusItemCaptureBandRejectsApplicationMenuFrames() {
        let window = CGRect(x: 0, y: 0, width: 1280, height: 30)
        XCTAssertFalse(
            MenuBarItemImageCache.isInStatusItemCaptureBand(
                bounds: CGRect(x: 80, y: 3, width: 24, height: 24),
                windowFrame: window,
                applicationMenuMaxX: 420
            )
        )
        XCTAssertTrue(
            MenuBarItemImageCache.isInStatusItemCaptureBand(
                bounds: CGRect(x: 430, y: 3, width: 24, height: 24),
                windowFrame: window,
                applicationMenuMaxX: 420
            )
        )
        XCTAssertFalse(
            MenuBarItemImageCache.isInStatusItemCaptureBand(
                bounds: CGRect(x: 900, y: 3, width: 24, height: 24),
                windowFrame: window,
                applicationMenuMaxX: nil
            )
        )
    }

    @available(macOS 27, *)
    func testStableCaptureBoundsAllowSubpixelAXJitter() {
        XCTAssertTrue(
            MenuBarItemImageCache.hasStableCaptureBounds(
                before: CGRect(x: 100, y: 3, width: 24, height: 24),
                after: CGRect(x: 100.5, y: 3, width: 24, height: 24)
            )
        )
    }

    @available(macOS 27, *)
    func testStableCaptureBoundsRejectHorizontalReflow() {
        XCTAssertFalse(
            MenuBarItemImageCache.hasStableCaptureBounds(
                before: CGRect(x: 100, y: 3, width: 24, height: 24),
                after: CGRect(x: 124, y: 3, width: 24, height: 24)
            )
        )
    }

    @available(macOS 27, *)
    func testStableCaptureBoundsRejectResizedSlot() {
        XCTAssertFalse(
            MenuBarItemImageCache.hasStableCaptureBounds(
                before: CGRect(x: 100, y: 3, width: 24, height: 24),
                after: CGRect(x: 100, y: 3, width: 48, height: 24)
            )
        )
    }

    @available(macOS 27, *)
    func testPrefersDisplayStripCaptureForThirdPartyAndThaw() {
        let thirdParty = MenuBarItemTag(namespace: .string("com.openai.chat"), title: "Item-0")
        let menuBarAgent = MenuBarItemTag(namespace: .menuBarAgent, title: "Clock")
        let thaw = MenuBarItemTag(namespace: .thaw, title: "Thaw.ControlItem.Visible")

        // Only genuine Apple modules composite cleanly in the hosting window.
        XCTAssertTrue(MenuBarItemImageCache.prefersDisplayStripCapture(for: thirdParty))
        XCTAssertFalse(MenuBarItemImageCache.prefersDisplayStripCapture(for: menuBarAgent))
        // Thaw's own control item is a third-party Liquid Glass item for capture
        // purposes and shreds in the hosting window — read it from the strip.
        XCTAssertTrue(MenuBarItemImageCache.prefersDisplayStripCapture(for: thaw))
    }

    private func makeItem(
        tag: MenuBarItemTag = .appItem(bundleID: "com.test.capture", title: "Capture"),
        bounds: CGRect? = nil
    ) -> MenuBarItem {
        MenuBarItem(
            tag: tag,
            windowID: 42,
            ownerPID: 100,
            sourcePID: 100,
            bounds: bounds ?? cachedBounds,
            title: "Capture",
            isOnScreen: true
        )
    }
}
