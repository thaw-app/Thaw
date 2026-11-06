//
//  AXCropRules.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import ThawCapture

/// The rejection rules one Accessibility-bounds crop must pass, in the order they run.
nonisolated enum AXCropRules {
    static let diagLog = MenuBarItemImageCache.diagLog

    /// What one capture source's crops are checked against, gathered from that source's acquisition.
    struct SourceRules {
        let knockOutBackground: Bool
        let validateFreshBounds: Bool
        let absenceMeansMoved: Bool
        let postCaptureBoundsByID: [String: CGRect]
        let captureTimeBoundsByID: [String: CGRect]
        let overflowBounds: [CGRect]
        let concealedIdentifiers: Set<String>
        let ambiguousIdentifiers: Set<String>
        let forgivenTags: Set<MenuBarItemTag>
    }

    /// One item to crop, and the screenshot it is cut from.
    struct Candidate {
        let item: MenuBarItem
        let bounds: CGRect
        let capture: ScreenCapture.MenuBarHostingCapture
        let source: CaptureSource
    }

    /// How a rejected candidate changes the pass. Every rejection makes the item unreadable.
    enum Rejection: Error, Equatable {
        /// The prior image stays.
        case keepPrior
        /// The prior image goes unless it looks settled.
        case invalidate
        /// The prior image goes even when it looks settled.
        case invalidateUnconditionally
        /// The crop itself failed, which counts against the failure ledger.
        case failedCrop
        /// Another item from the same source already claimed this crop rectangle, so both lose.
        case sharesCropRect(with: MenuBarItemTag)
    }

    enum Verdict {
        case cropped(MenuBarItemGlyphCapture, cropRect: CGRect)
        case rejected(Rejection)
    }

    /// Runs every rule against one candidate.
    ///
    /// - Parameters:
    ///   - claimedCropRects: Crop rectangles earlier candidates from the same source were published under.
    ///   - displayBounds: Read only when the item lies outside the capture.
    ///   - shouldSkip: Asked only for an item the pass did not forgive.
    static func verdict(
        for candidate: Candidate,
        rules: SourceRules,
        claimedCropRects: [CGRect: MenuBarItemTag],
        displayBounds: () -> [CGRect],
        shouldSkip: (MenuBarItem) -> Bool
    ) -> Verdict {
        if let rejection = identityRejection(candidate, rules: rules, shouldSkip: shouldSkip)
            ?? freshnessRejection(candidate, rules: rules)
            ?? placementRejection(candidate, displayBounds: displayBounds)
        {
            return .rejected(rejection)
        }
        let rawCrop: (image: CGImage, cropRect: CGRect)
        let image: CGImage
        do throws(Rejection) {
            rawCrop = try cut(candidate, claimedCropRects: claimedCropRects)
            image = try cleaned(rawCrop.image, candidate: candidate, rules: rules)
        } catch {
            return .rejected(error)
        }
        if let rejection = imageRejection(image, candidate: candidate) {
            return .rejected(rejection)
        }
        return .cropped(MenuBarItemGlyphCapture(cgImage: image, scale: candidate.capture.scale), cropRect: rawCrop.cropRect)
    }

    /// The ledger, ownership, concealment, overflow and neighbour rules.
    private static func identityRejection(
        _ candidate: Candidate,
        rules: SourceRules,
        shouldSkip: (MenuBarItem) -> Bool
    ) -> Rejection? {
        let (item, bounds) = (candidate.item, candidate.bounds)
        if !rules.forgivenTags.contains(item.tag), shouldSkip(item) {
            return .keepPrior
        }
        if rules.ambiguousIdentifiers.contains(item.uniqueIdentifier) {
            diagLog.debug(
                "CaptureOwnershipTrace: rejecting ambiguous owner for \(item.logString) at \(bounds); invalidating prior glyph"
            )
            return .invalidateUnconditionally
        }
        // A concealed item's stale bounds crop whatever now sits there. Test the concealment set, since the
        // AX provider reports isOnScreen: true for every item.
        if ItemConcealment.isConcealed(item.uniqueIdentifier, in: rules.concealedIdentifiers) {
            // Applies to hiding-unsupported items too: the assertion claims them.
            diagLog.debug(
                "axBoundsCapture: \(item.logString) is concealed; keeping its prior image " +
                    "rather than cropping \(item.tag.isHidingUnsupported ? "the bar behind it" : "its stale bounds")"
            )
            // Keep the old glyph: the prewarm's temporary reveal is the only
            // other source, and it can yield no crop.
            return .keepPrior
        }
        if isContaminatedByNativeOverflow(bounds, overflowBounds: rules.overflowBounds) {
            diagLog.debug(
                "axBoundsCapture: overflow geometry changed while capturing \(item.logString); " +
                    "clearing prior image for app-icon fallback"
            )
            return .invalidate
        }
        // Ahead of the freshness check, which keeps the prior image when it
        // cannot re-read bounds. Bounds that swallow a neighbour are wrong either way.
        if let covered = coveredIdentifier(bounds, ownIdentifier: item.uniqueIdentifier, liveBounds: rules.captureTimeBoundsByID) {
            diagLog.debug(
                "axBoundsCapture: \(item.logString) bounds \(bounds) cover \(covered); " +
                    "clearing prior image for app-icon fallback"
            )
            return .invalidateUnconditionally
        }
        return nil
    }

    /// Only a re-read rect that disagrees costs the capture. Absence is not
    /// movement: some apps vend their AX element intermittently.
    private static func freshnessRejection(_ candidate: Candidate, rules: SourceRules) -> Rejection? {
        guard rules.validateFreshBounds else { return nil }
        let (item, bounds) = (candidate.item, candidate.bounds)
        if let postCaptureBounds = rules.postCaptureBoundsByID[item.uniqueIdentifier] {
            guard hasStableCaptureBounds(before: bounds, after: postCaptureBounds) else {
                diagLog.debug(
                    // A delta shared by every item means stale bounds or a
                    // coordinate-basis bug, not movement.
                    "axBoundsCapture: bounds changed while capturing \(item.logString); keeping prior image (before=\(bounds.debugDescription) after=\(postCaptureBounds.debugDescription))"
                )
                return .keepPrior
            }
            return nil
        }
        if rules.absenceMeansMoved {
            // The map came from the identity catalog, so no entry means
            // the item is not where the crop was cut.
            diagLog.debug(
                "axBoundsCapture: \(item.logString) has no live frame at \(bounds.debugDescription); keeping prior image"
            )
            return .keepPrior
        }
        diagLog.debug(
            "axBoundsCapture: \(item.logString) absent from the post-capture read; " +
                "keeping the capture taken at \(bounds.debugDescription)"
        )
        return nil
    }

    /// Bounds outside the captured window: another display's bar, or parked off every bar.
    private static func placementRejection(_ candidate: Candidate, displayBounds: () -> [CGRect]) -> Rejection? {
        let (item, bounds) = (candidate.item, candidate.bounds)
        let windowFrame = candidate.capture.windowFrame
        guard !windowFrame.intersects(bounds) else { return nil }
        if liesOnAMenuBar(bounds, barHeight: windowFrame.height, displayBounds: displayBounds()) {
            diagLog.debug(
                "axBoundsCapture: \(item.logString) bounds \(bounds) are on another display's bar; keeping prior image"
            )
            return .keepPrior
        }
        // macOS 27 parks concealed items far below the bar (y≈1428). Drop
        // the prior image without blacklisting so the app icon shows.
        diagLog.debug(
            "axBoundsCapture: \(item.logString) bounds \(bounds) outside \(candidate.source.rawValue) " +
                "frame \(windowFrame); clearing prior image for app-icon fallback"
        )
        return .invalidate
    }

    /// The raw pixels under the item's bounds, and the rectangle they were cut from.
    private static func cut(
        _ candidate: Candidate,
        claimedCropRects: [CGRect: MenuBarItemTag]
    ) throws(Rejection) -> (image: CGImage, cropRect: CGRect) {
        let (item, bounds, capture) = (candidate.item, candidate.bounds, candidate.capture)
        let sourceLabel = candidate.source.rawValue
        // cropMapping is shared with the capture inspector so both agree on
        // which pixels belong to an item.
        guard let mapping = capture.cropMapping(forItemBounds: bounds) else {
            diagLog.debug(
                "axBoundsCapture: degenerate \(sourceLabel) geometry for \(item.logString) " +
                    "bounds=\(bounds) frame=\(capture.windowFrame) scale=\(capture.scale); " +
                    "clearing prior image for app-icon fallback"
            )
            throw .invalidate
        }
        let cropRect = mapping.clamped
        guard mapping.isComplete else {
            // Overflowed items sit mostly outside the frame and crop to a
            // sliver. Treat that as no capture so the app icon shows.
            diagLog.debug(
                "axBoundsCapture: incomplete \(sourceLabel) frame for \(item.logString) " +
                    "rawCropRect=\(mapping.raw) expected=\(mapping.expected) clamped=\(cropRect); " +
                    "clearing prior image for app-icon fallback"
            )
            throw .invalidate
        }
        // On macOS 27 overflow-hidden items can share identical AX bounds.
        // Neither crop is trustworthy, so both fall back to the app icon.
        if let priorTag = claimedCropRects[cropRect] {
            diagLog.debug(
                "axBoundsCapture: duplicate crop rect \(cropRect) for " +
                    "\(item.logString); clearing both items for app-icon fallback"
            )
            throw .sharesCropRect(with: priorTag)
        }
        guard !cropRect.isNull, !cropRect.isEmpty, let rawCroppedImage = capture.image.cropping(to: cropRect) else {
            diagLog.debug(
                "axBoundsCapture: cropping failed for \(item.logString) " +
                    "rawCropRect=\(mapping.raw) clamped=\(cropRect)"
            )
            throw .failedCrop
        }
        return (rawCroppedImage, cropRect)
    }

    /// The crop with its background removed. A strip crop that can't be knocked out (busy wallpaper) fails,
    /// since the raw crop would cache the wallpaper.
    private static func cleaned(_ rawCroppedImage: CGImage, candidate: Candidate, rules: SourceRules) throws(Rejection) -> CGImage {
        let item = candidate.item
        let sourceLabel = candidate.source.rawValue
        let croppedImage: CGImage
        CaptureDiagnostics.record(rawCroppedImage, item: item, bounds: candidate.bounds, source: sourceLabel)
        if candidate.source != .displayStrip, rawCroppedImage.hasOpaquePerimeter() {
            // Opaque means SkyLight's blank slab or a glyph on a solid bar;
            // the knock-out tells them apart, the strip takes the rest.
            let separated = rawCroppedImage.separatedFromNearUniformBackground()
            guard separated.presence == .present, let cleaned = separated.image else {
                diagLog.debug(
                    "axBoundsCapture: opaque \(sourceLabel) crop for \(item.logString) reads " +
                        "\(String(describing: separated.presence)); leaving it to the display strip"
                )
                throw .invalidate
            }
            croppedImage = cleaned
        } else if rules.knockOutBackground {
            guard let cleaned = rawCroppedImage.knockingOutNearUniformBackground() else {
                diagLog.debug(
                    "axBoundsCapture: could not separate \(item.logString) from the menu bar " +
                        "background; clearing prior image for app-icon fallback"
                )
                throw .invalidate
            }
            croppedImage = cleaned // already a fresh makeImage(), do not detach again
        } else {
            croppedImage = rawCroppedImage.detachedCopy()
        }
        CaptureDiagnostics.recordCleaned(croppedImage, item: item, source: sourceLabel)
        return croppedImage
    }

    /// The size, slab, blank and chevron rules on the finished crop.
    private static func imageRejection(_ croppedImage: CGImage, candidate: Candidate) -> Rejection? {
        let (item, bounds) = (candidate.item, candidate.bounds)
        let sourceLabel = candidate.source.rawValue
        // A crop larger than the item's frame carries a neighbour's pixels.
        // Invalidating clears a blank prior but keeps a settled one.
        guard isCropWithinItemBounds(
            imageWidth: croppedImage.width,
            imageHeight: croppedImage.height,
            itemBounds: bounds,
            scale: candidate.capture.scale
        ) else {
            diagLog.debug(
                "axBoundsCapture: \(item.logString) \(sourceLabel) crop " +
                    "\(croppedImage.width)×\(croppedImage.height)px exceeds its bounds " +
                    "\(bounds.debugDescription); discarding crop"
            )
            return .invalidate
        }
        // An opaque border is the blank slab SkyLight answers with for a window
        // it is not compositing. Invalidating clears a blank prior, keeps a settled one.
        guard !croppedImage.hasOpaquePerimeter() else {
            diagLog.debug("axBoundsCapture: opaque-border \(sourceLabel) crop for \(item.logString); discarding crop")
            return .invalidate
        }
        guard !croppedImage.isTransparent(alphaThreshold: 0.05) else {
            return blankRejection(of: item)
        }
        // Items collapsed into the overflow chevron keep AX bounds over it, and their crop passes every check above.
        if bounds.width < MenuBarItemImageCache.minimumTrustedGlyphWidth, !item.tag.isLayoutAnchoredSystemItem {
            diagLog.debug(
                "axBoundsCapture: rejecting suspiciously narrow crop " +
                    "(\(bounds.width)pt) for \(item.logString); likely overflow chevron bleed"
            )
            return .invalidate
        }
        return nil
    }

    private static func blankRejection(of item: MenuBarItem) -> Rejection {
        // These render blank briefly during a reflow. A recorded failure
        // would blacklist them for 30 s, so keep the last good image.
        if item.tag.isHidingUnsupported || item.tag.isNonConcealableSystemItem {
            diagLog.debug(
                "axBoundsCapture: blank image for reflow-transient \(item.logString); " +
                    "skipping without failure (will recover on next refresh)"
            )
            return .keepPrior
        }
        // Anything reaching here is on-screen. Clear the prior, which may
        // be a stale crop from bad geometry.
        diagLog.debug(
            "axBoundsCapture: blank image for \(item.logString); " +
                "clearing prior image for app-icon fallback"
        )
        return .invalidate
    }
}

extension MenuBarItemImageCache.CapturePass {
    mutating nonisolated func record(_ verdict: AXCropRules.Verdict, for item: MenuBarItem) {
        switch verdict {
        case let .cropped(glyph, _):
            recoveredItems.append(item)
            captured[item.tag] = glyph
        case let .rejected(rejection):
            reject(item, rejection)
        }
    }

    mutating nonisolated func reject(_ item: MenuBarItem, _ rejection: AXCropRules.Rejection) {
        switch rejection {
        case .keepPrior:
            break
        case .invalidate:
            invalidatedTags.insert(item.tag)
        case .invalidateUnconditionally:
            invalidatedTags.insert(item.tag)
            unconditionallyInvalidatedTags.insert(item.tag)
        case .failedCrop:
            failedCaptureItems.append(item)
        case let .sharesCropRect(priorTag):
            captured.removeValue(forKey: priorTag)
            invalidatedTags.formUnion([priorTag, item.tag])
            unconditionallyInvalidatedTags.formUnion([priorTag, item.tag])
        }
        unreadable.append(item)
    }

    /// Records items whose pixels did not arrive. A capture refused because no Thaw surface is open
    /// proves nothing about the pictures already cached, so it records nothing and returns false.
    @discardableResult
    mutating nonisolated func noteMissingCapture(of items: [MenuBarItem], captureWasAllowed: Bool) -> Bool {
        guard captureWasAllowed else { return false }
        unreadable.append(contentsOf: items)
        invalidatedTags.formUnion(items.map(\.tag))
        return true
    }
}
