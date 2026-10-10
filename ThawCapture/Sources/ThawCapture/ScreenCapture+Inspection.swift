//
//  ScreenCapture+Inspection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel

// The "what Thaw sees" promise holds only if it is structural. Inspection
// calls the very functions the capture pipeline calls and adds no
// ScreenCaptureKit code of its own, so it cannot succeed where the pipeline
// fails or show a frame the pipeline never read. CropMapping is the single
// definition of crop geometry, used by both the inspector and the pipeline,
// so the two cannot drift apart.

public extension ScreenCapture {
    // MARK: - Crop geometry

    /// How one item's on-screen frame lands inside a capture image.
    ///
    /// Held together as one value because the crop decision needs all three
    /// rects: raw documents the unrounded mapping, expected is what the
    /// glyph would occupy given whole pixels, and clamped is what can actually
    /// be read. A large gap between the last two means the item sits partly
    /// outside the frame, which is what isComplete reports.
    struct CropMapping: Equatable, Sendable {
        /// The item's frame mapped into image pixels, before rounding.
        public let raw: CGRect
        /// raw rounded outward to whole pixels.
        ///
        /// Outward rather than nearest: a sub-pixel origin or size would
        /// otherwise shave a column off the glyph's edge, which reads as an
        /// intermittently cut icon.
        public let expected: CGRect
        /// expected confined to the image, and so the rect that can be read.
        public let clamped: CGRect
        /// Whether clamping cost the crop nothing meaningful.
        ///
        /// An item that is natively hidden or has overflowed sits mostly
        /// outside the captured frame, leaving a sliver that is not its glyph.
        public let isComplete: Bool
    }

    /// The pixel rect covering a capture image, in the space CropMapping uses.
    static func imageBounds(
        ofWidth width: Int,
        height: Int
    ) -> CGRect {
        CGRect(x: 0, y: 0, width: width, height: height)
    }

    /// Maps a menu bar item's frame into a capture image.
    ///
    /// Both frames are global and Y-down, and CGImage rows also run top-down,
    /// so the mapping is a translation by the capture's origin followed by a
    /// scale to pixels, no axis flip.
    ///
    /// - Parameters:
    ///   - itemBounds: The item's frame in global screen coordinates.
    ///   - captureFrame: The captured region's frame in the same coordinates.
    ///   - scale: The pixel scale the image was captured at.
    ///   - imageBounds: The image's pixel rect.
    ///   - edgeTolerance: How much clamping to forgive per edge, in pixels.
    /// - Returns: The mapping, or nil if the geometry is degenerate.
    static func cropMapping(
        itemBounds: CGRect,
        captureFrame: CGRect,
        scale: CGFloat,
        imageBounds: CGRect,
        edgeTolerance: CGFloat = 1
    ) -> CropMapping? {
        guard scale > 0, scale.isFinite,
              !itemBounds.isNull, !itemBounds.isEmpty,
              itemBounds.width.isFinite, itemBounds.height.isFinite,
              !captureFrame.isNull, !imageBounds.isNull, !imageBounds.isEmpty
        else {
            return nil
        }

        let raw = CGRect(
            x: (itemBounds.minX - captureFrame.minX) * scale,
            y: (itemBounds.minY - captureFrame.minY) * scale,
            width: itemBounds.width * scale,
            height: itemBounds.height * scale
        )
        let expected = raw.integral
        let clamped = expected.intersection(imageBounds)

        return CropMapping(
            raw: raw,
            expected: expected,
            clamped: clamped,
            isComplete: isCompleteCrop(
                expected: expected,
                clamped: clamped,
                edgeTolerance: edgeTolerance
            )
        )
    }

    /// Whether a clamped crop still covers what was expected of it.
    static func isCompleteCrop(
        expected: CGRect,
        clamped: CGRect,
        edgeTolerance: CGFloat = 1
    ) -> Bool {
        guard !expected.isNull, !expected.isEmpty, !clamped.isNull, !clamped.isEmpty else {
            return false
        }

        return clamped.minX - expected.minX <= edgeTolerance
            && clamped.minY - expected.minY <= edgeTolerance
            && expected.maxX - clamped.maxX <= edgeTolerance
            && expected.maxY - clamped.maxY <= edgeTolerance
    }
}

public extension ScreenCapture.MenuBarHostingCapture {
    /// The captured image's pixel rect.
    var imageBounds: CGRect {
        ScreenCapture.imageBounds(ofWidth: image.width, height: image.height)
    }

    /// Maps an item's on-screen frame into this capture.
    func cropMapping(
        forItemBounds itemBounds: CGRect,
        edgeTolerance: CGFloat = 1
    ) -> ScreenCapture.CropMapping? {
        ScreenCapture.cropMapping(
            itemBounds: itemBounds,
            captureFrame: windowFrame,
            scale: scale,
            imageBounds: imageBounds,
            edgeTolerance: edgeTolerance
        )
    }
}

// MARK: - Inspection

public extension ScreenCapture {
    /// Everything Thaw read from one display in a single pass, untouched.
    ///
    /// A nil frame is a meaningful answer rather than an error: with Screen
    /// Recording ungranted, both are nil, and that is the verification,
    /// Thaw is reading nothing.
    struct CaptureInspection: @unchecked Sendable {
        /// The display this pass read.
        public let displayID: CGDirectDisplayID
        /// When the frames were taken.
        public let capturedAt: Date

        /// The frame Thaw crops item images out of.
        ///
        /// This is the only region of the user's screen Thaw reads, and it
        /// contains whatever else lives there, the frontmost app's menus, the
        /// wallpaper behind the bar. Showing that honestly is the point.
        public let primary: MenuBarHostingCapture?

        /// MenuBarAgent's hosting surface, which holds the status item glyphs
        /// composited on a transparent background.
        ///
        /// Captured but not surfaced in the UI: the window is off-screen, so the
        /// frame reads as a rendering bug next to the strip. It stays here
        /// because the pipeline does take it.
        public let hosting: MenuBarHostingCapture?

        /// Whether the pass read any pixels at all.
        public var isEmpty: Bool {
            primary == nil && hosting == nil
        }
    }

    /// The region of a display Thaw reads, without reading it.
    ///
    /// Derived from the same function the capture configures itself with, so a
    /// scope shown to the user cannot drift from the scope actually taken.
    ///
    /// - Parameters:
    ///   - displayFrame: The display's frame.
    ///   - menuBarHeight: The display's live menu bar height, nil if unknown.
    static func inspectableStripFrame(displayFrame: CGRect, menuBarHeight: CGFloat? = nil) -> CGRect {
        menuBarDisplayStripFrame(
            displayFrame: displayFrame,
            height: menuBarDisplayStripHeight(menuBarHeight: menuBarHeight)
        )
    }

    /// Captures both frames for a display so they can be shown to the user.
    ///
    /// The two captures run concurrently and independently; one failing does not
    /// suppress the other, because a half-answer is still evidence.
    ///
    /// - Parameter displayID: The display to inspect.
    /// - Returns: The pass, with a nil frame for each capture that failed.
    static func inspect(displayID: CGDirectDisplayID) async -> CaptureInspection {
        async let strip = captureMenuBarDisplayStripAsync(displayID: displayID)
        async let hosting = captureMenuBarHostingWindowAsync(displayID: displayID)

        let inspection = await CaptureInspection(
            displayID: displayID,
            capturedAt: Date(),
            primary: strip,
            hosting: hosting
        )

        diagLog.debug(
            "inspect: displayID=\(displayID) strip=\(inspection.primary != nil) " +
                "hosting=\(inspection.hosting != nil)"
        )
        return inspection
    }
}
