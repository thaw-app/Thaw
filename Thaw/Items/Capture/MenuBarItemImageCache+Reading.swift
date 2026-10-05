//
//  MenuBarItemImageCache+Reading.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import ThawCapture

extension MenuBarItemImageCache {
    // MARK: Reading Pixels

    /// Checks which of the given items currently render as blank pixels in the
    /// real menu bar, independent of this cache's own stored images.
    ///
    /// A restriction reflow can leave an item hit-testable but undrawn, and the
    /// cache often has no entry for visible items, so only a fresh screenshot
    /// shows whether the OS redrew the glyph.
    nonisolated func itemsRenderingBlank(
        among items: [MenuBarItem],
        displayID: CGDirectDisplayID
    ) async -> Set<MenuBarItemTag> {
        guard !items.isEmpty else { return [] }

        guard let capture = await ScreenCapture.captureMenuBarHostingWindowAsync(displayID: displayID) else {
            return []
        }
        return Self.blankTags(in: items, from: capture)
    }

    static nonisolated func blankTags(
        in items: [MenuBarItem],
        from capture: ScreenCapture.MenuBarHostingCapture
    ) -> Set<MenuBarItemTag> {
        let composite = capture.image

        var blankTags = Set<MenuBarItemTag>()
        for item in items {
            guard capture.windowFrame.intersects(item.bounds),
                  let mapping = capture.cropMapping(forItemBounds: item.bounds),
                  !mapping.clamped.isNull, !mapping.clamped.isEmpty,
                  let croppedImage = composite.cropping(to: mapping.clamped)
            else {
                continue
            }
            if croppedImage.isTransparent() {
                blankTags.insert(item.tag)
            }
        }
        return blankTags
    }

    /// One capture's reading of the items it was asked about.
    ///
    /// A tag in neither set was undecidable (outside the frame, or not
    /// separable from its background), which is not the same as blank.
    struct CaptureVerdict {
        /// The tags that rendered pixels.
        var seen = Set<MenuBarItemTag>()

        /// The tags that rendered nothing.
        var blank = Set<MenuBarItemTag>()

        mutating func formUnion(_ other: CaptureVerdict) {
            seen.formUnion(other.seen)
            blank.formUnion(other.blank)
        }
    }

    /// Reads items out of capture, saying for each one whether it rendered.
    ///
    /// Unlike blankTags(in:from:) this separates "rendered nothing" from
    /// "this capture cannot say".
    ///
    /// - Parameter knockingOutBackground: Pass true for a display-strip
    ///   capture, whose empty slots are opaque bar fill rather than
    ///   transparent. Hosting-window crops are already transparent.
    static nonisolated func verdict(
        for items: [MenuBarItem],
        from capture: ScreenCapture.MenuBarHostingCapture,
        knockingOutBackground: Bool
    ) -> CaptureVerdict {
        let composite = capture.image

        var verdict = CaptureVerdict()
        for item in items {
            // Containment, not intersection: a clipped frame renders short and
            // the shortfall looks like absence.
            guard capture.windowFrame.contains(item.bounds),
                  let mapping = capture.cropMapping(forItemBounds: item.bounds),
                  !mapping.clamped.isNull, !mapping.clamped.isEmpty,
                  let rawCrop = composite.cropping(to: mapping.clamped)
            else {
                continue
            }

            guard knockingOutBackground else {
                if rawCrop.isTransparent() {
                    verdict.blank.insert(item.tag)
                } else {
                    verdict.seen.insert(item.tag)
                }
                continue
            }

            switch rawCrop.glyphPresenceOverNearUniformBackground() {
            case .present:
                verdict.seen.insert(item.tag)
            case .absent:
                verdict.blank.insert(item.tag)
            case .indeterminate:
                // Not separable from the wallpaper, so no answer either way.
                continue
            }
        }
        return verdict
    }

    /// Whether a clamped crop still covers what was expected of it.
    ///
    /// Delegates so the pipeline and the capture inspector share one rule.
    static nonisolated func isCompleteCrop(
        expected: CGRect,
        clamped: CGRect,
        edgeTolerance: CGFloat = 1
    ) -> Bool {
        ScreenCapture.isCompleteCrop(
            expected: expected,
            clamped: clamped,
            edgeTolerance: edgeTolerance
        )
    }

    /// The item that already claimed these crop pixels in the current pass.
    /// AX can temporarily assign identical frames to distinct macOS 27 items
    /// while MenuBarAgent reflows an overflowed section.
    static nonisolated func cropRectOwner(
        _ cropRect: CGRect,
        cropRectOwners: [CGRect: MenuBarItemTag]
    ) -> MenuBarItemTag? {
        cropRectOwners[cropRect]
    }

    /// The identifier of an item whose glyph bounds mostly covers, if any.
    ///
    /// Catches a rect that swallows a neighbour (a 195pt sound module over a
    /// 27pt item), which neither the shared-rect check nor the 200pt cap sees.
    /// Coverage and relative width only count together, since wide items and
    /// small reflow overlaps are both benign.
    static nonisolated func coveredIdentifier(
        _ bounds: CGRect,
        ownIdentifier: String,
        liveBounds: [String: CGRect],
        minimumCoverage: CGFloat = 0.9,
        minimumWidthRatio: CGFloat = 1.5
    ) -> String? {
        guard !bounds.isEmpty else { return nil }
        // Measured on x alone: every item shares the bar's height, so vertical
        // overlap is true of any two items and carries no information.
        return liveBounds
            .lazy
            .filter { $0.key != ownIdentifier && !$0.value.isEmpty }
            .first { other in
                // Near-total containment, and wider than the neighbour: a 14pt
                // item can cover another 14pt item without engulfing it.
                let overlap = min(bounds.maxX, other.value.maxX) - max(bounds.minX, other.value.minX)
                return overlap > 0
                    && overlap >= other.value.width * minimumCoverage
                    && bounds.width >= other.value.width * minimumWidthRatio
            }?
            .key
    }

    static nonisolated func isContaminatedByNativeOverflow(
        _ bounds: CGRect,
        overflowBounds: [CGRect],
        minimumOverflowCoverage: CGFloat = nativeOverflowCoverageFraction
    ) -> Bool {
        overflowBounds.contains { overflow in
            let overlap = bounds.intersection(overflow).width
            return overlap >= overflow.width * minimumOverflowCoverage
        }
    }

    /// The share of an overflow control's width a crop must overlap before
    /// the chevron glyphs can appear inside it.
    ///
    /// macOS 27 parks concealed items in stacks that graze the chevron's
    /// frame; a one-point graze is not contamination.
    static nonisolated let nativeOverflowCoverageFraction: CGFloat = 0.5

    /// Whether this pass must not read pixels from the item's reported
    /// frame.
    ///
    /// A frame another on-band item occupies (hasPhantomFrame) or one parked
    /// off the band crops someone else's pixels; skip it rather than fail.
    static nonisolated func hasUnusableCaptureGeometry(
        _ item: MenuBarItem,
        among peers: [MenuBarItem]
    ) -> Bool {
        item.hasPhantomFrame(among: peers) || item.isParkedOffMenuBarBand(among: peers)
    }

    /// Rejects hosting-window screenshots whose pixel size does not match
    /// windowFrame * scale. After a display-mode flip AppKit and
    /// ScreenCaptureKit can disagree on scale, and crops land on wrong regions.
    static nonisolated func isPlausibleHostingCapture(
        imageWidth: Int,
        imageHeight: Int,
        windowFrame: CGRect,
        scale: CGFloat,
        tolerance: CGFloat = 2
    ) -> Bool {
        guard scale > 0, scale.isFinite,
              windowFrame.width > 0, windowFrame.height > 0,
              windowFrame.width.isFinite, windowFrame.height.isFinite,
              imageWidth > 0, imageHeight > 0
        else {
            return false
        }

        let expectedWidth = windowFrame.width * scale
        let expectedHeight = windowFrame.height * scale
        return abs(CGFloat(imageWidth) - expectedWidth) <= tolerance
            && abs(CGFloat(imageHeight) - expectedHeight) <= tolerance
    }

    /// Rejects AX frames too wide to be a single status glyph, which would
    /// otherwise cache near-full-bar bitmaps.
    static nonisolated func isPlausibleItemCaptureBounds(
        _ bounds: CGRect,
        maxWidthPoints: CGFloat = 200
    ) -> Bool {
        guard !bounds.isNull, !bounds.isEmpty,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0
        else {
            return false
        }

        // A hard point cap: a fraction of the bar admits app-menu-wide frames.
        return bounds.width <= maxWidthPoints
    }

    /// Whether a finished crop still fits the item's own frame. Oversized pixels come
    /// from a stale rect or scale mismatch and would carry a neighbour's glyph.
    static nonisolated func isCropWithinItemBounds(
        imageWidth: Int,
        imageHeight: Int,
        itemBounds: CGRect,
        scale: CGFloat,
        tolerancePoints: CGFloat = 2
    ) -> Bool {
        guard scale > 0, scale.isFinite,
              !itemBounds.isNull, !itemBounds.isEmpty,
              itemBounds.width > 0, itemBounds.height > 0
        else {
            return false
        }
        return CGFloat(imageWidth) / scale <= itemBounds.width + tolerancePoints
            && CGFloat(imageHeight) / scale <= itemBounds.height + tolerancePoints
    }

    /// Status-item glyphs live right of the application menu; a frame in the
    /// app-menu band would crop menu text into the glyph cache.
    static nonisolated func isInStatusItemCaptureBand(
        bounds: CGRect,
        applicationMenuMaxX: CGFloat?,
        leadingTolerance: CGFloat = 2
    ) -> Bool {
        guard !bounds.isNull, !bounds.isEmpty else { return false }

        if let applicationMenuMaxX, applicationMenuMaxX.isFinite {
            return bounds.minX >= applicationMenuMaxX - leadingTolerance
        }

        // No percentage fallback: menu widths vary too much. Miss until AX
        // supplies the boundary.
        return false
    }

    static nonisolated func hasStableCaptureBounds(
        before: CGRect,
        after: CGRect,
        tolerance: CGFloat = 1.0
    ) -> Bool {
        abs(before.minX - after.minX) <= tolerance
            && abs(before.minY - after.minY) <= tolerance
            && abs(before.width - after.width) <= tolerance
            && abs(before.height - after.height) <= tolerance
    }

    /// Whether a captured scale is one a display could actually have produced.
    static nonisolated func isPlausibleCaptureScale(_ scale: CGFloat) -> Bool {
        guard scale.isFinite, scale > 0 else { return false }
        return [1.0, 2.0, 3.0].contains { abs(scale - $0) <= 0.02 }
    }

    /// Which window a crop was taken from.
    ///
    /// An enum, not a string, because the bar-window case steers the crop and
    /// a typo must not skip the opaque-slab guard.
    nonisolated enum CaptureSource: String {
        case hosting
        case barWindow = "bar-window"
        case displayStrip = "display-strip"
    }

    /// Crops one capture source into result, mutating shared pass state.
    nonisolated func appendAXBoundsCrops(
        from candidates: [(item: MenuBarItem, bounds: CGRect)],
        capture: ScreenCapture.MenuBarHostingCapture,
        source: CaptureSource,
        knockOutBackground: Bool,
        validateFreshBounds: Bool,
        absenceMeansMoved: Bool,
        postCaptureBoundsByID: [String: CGRect],
        captureTimeBoundsByID: [String: CGRect],
        overflowBounds: [CGRect],
        concealedIdentifiers: Set<String>,
        ambiguousIdentifiers: Set<String>,
        forgivenTags: Set<MenuBarItemTag>,
        cropRectOwners: inout [CGRect: MenuBarItemTag],
        into result: inout CapturePass
    ) {
        let sourceLabel = source.rawValue
        let composite = capture.image
        let windowFrame = capture.windowFrame
        let scale = capture.scale

        for (item, bounds) in candidates {
            if !forgivenTags.contains(item.tag), shouldSkipCapture(for: item) {
                result.unreadable.append(item)
                continue
            }

            if ambiguousIdentifiers.contains(item.uniqueIdentifier) {
                MenuBarItemImageCache.diagLog.debug(
                    "CaptureOwnershipTrace: rejecting ambiguous owner for \(item.logString) at \(bounds); invalidating prior glyph"
                )
                result.unreadable.append(item)
                result.invalidatedTags.insert(item.tag)
                result.unconditionallyInvalidatedTags.insert(item.tag)
                continue
            }

            // A concealed item is removed from MenuBarAgent, so its stale bounds
            // crop whatever now sits there. The concealment set is the test,
            // because the AX provider reports isOnScreen: true for every item.
            if concealedIdentifiers.contains(
                MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)
            ) {
                // Applies to hiding-unsupported items too: the assertion claims them.
                MenuBarItemImageCache.diagLog.debug(
                    "axBoundsCapture: \(item.logString) is concealed; keeping its prior image " +
                        "rather than cropping \(item.tag.isHidingUnsupported ? "the bar behind it" : "its stale bounds")"
                )
                // Keep the old glyph: the prewarm's temporary reveal is the only
                // other source, and it can yield no crop.
                result.unreadable.append(item)
                continue
            }

            if Self.isContaminatedByNativeOverflow(bounds, overflowBounds: overflowBounds) {
                MenuBarItemImageCache.diagLog.debug(
                    "axBoundsCapture: overflow geometry changed while capturing \(item.logString); " +
                        "clearing prior image for app-icon fallback"
                )
                result.unreadable.append(item)
                result.invalidatedTags.insert(item.tag)
                continue
            }

            // Ahead of the freshness check, which keeps the prior image when it
            // cannot re-read bounds. Bounds that swallow a neighbour are wrong
            // either way.
            if let covered = Self.coveredIdentifier(
                bounds,
                ownIdentifier: item.uniqueIdentifier,
                liveBounds: captureTimeBoundsByID
            ) {
                MenuBarItemImageCache.diagLog.debug(
                    "axBoundsCapture: \(item.logString) bounds \(bounds) cover \(covered); " +
                        "clearing prior image for app-icon fallback"
                )
                result.unreadable.append(item)
                result.invalidatedTags.insert(item.tag)
                result.unconditionallyInvalidatedTags.insert(item.tag)
                continue
            }

            if validateFreshBounds {
                // Only a re-read rect that disagrees costs the capture. Absence
                // is not movement: some apps vend their AX element intermittently.
                if let postCaptureBounds = postCaptureBoundsByID[item.uniqueIdentifier] {
                    guard Self.hasStableCaptureBounds(before: bounds, after: postCaptureBounds) else {
                        MenuBarItemImageCache.diagLog.debug(
                            // A delta shared by every item means stale bounds or a
                            // coordinate-basis bug, not movement.
                            "axBoundsCapture: bounds changed while capturing \(item.logString); keeping prior image (before=\(bounds.debugDescription) after=\(postCaptureBounds.debugDescription))"
                        )
                        result.unreadable.append(item)
                        continue
                    }
                } else if absenceMeansMoved {
                    // The map came from the identity catalog, so no entry means
                    // the item is not where the crop was cut.
                    MenuBarItemImageCache.diagLog.debug(
                        "axBoundsCapture: \(item.logString) has no live frame at \(bounds.debugDescription); keeping prior image"
                    )
                    result.unreadable.append(item)
                    continue
                } else {
                    MenuBarItemImageCache.diagLog.debug(
                        "axBoundsCapture: \(item.logString) absent from the post-capture read; " +
                            "keeping the capture taken at \(bounds.debugDescription)"
                    )
                }
            }

            // macOS 27 parks concealed items far below the bar (y≈1428). Drop
            // the prior image without blacklisting so the app icon shows.
            if !windowFrame.intersects(bounds) {
                MenuBarItemImageCache.diagLog.debug(
                    "axBoundsCapture: \(item.logString) bounds \(bounds) outside \(sourceLabel) " +
                        "frame \(windowFrame); clearing prior image for app-icon fallback"
                )
                result.unreadable.append(item)
                result.invalidatedTags.insert(item.tag)
                continue
            }

            // cropMapping is shared with the capture inspector so both agree on
            // which pixels belong to an item.
            guard let mapping = capture.cropMapping(forItemBounds: bounds) else {
                MenuBarItemImageCache.diagLog.debug(
                    "axBoundsCapture: degenerate \(sourceLabel) geometry for \(item.logString) " +
                        "bounds=\(bounds) frame=\(windowFrame) scale=\(scale); " +
                        "clearing prior image for app-icon fallback"
                )
                result.unreadable.append(item)
                result.invalidatedTags.insert(item.tag)
                continue
            }
            let cropRect = mapping.clamped

            guard mapping.isComplete else {
                // Overflowed items sit mostly outside the frame and crop to a
                // sliver. Treat that as no capture so the app icon shows.
                MenuBarItemImageCache.diagLog.debug(
                    "axBoundsCapture: incomplete \(sourceLabel) frame for \(item.logString) " +
                        "rawCropRect=\(mapping.raw) expected=\(mapping.expected) clamped=\(cropRect); " +
                        "clearing prior image for app-icon fallback"
                )
                result.unreadable.append(item)
                result.invalidatedTags.insert(item.tag)
                continue
            }

            // On macOS 27 overflow-hidden items can share identical AX bounds.
            // Neither crop is trustworthy, so both fall back to the app icon.
            if let priorTag = Self.cropRectOwner(cropRect, cropRectOwners: cropRectOwners) {
                MenuBarItemImageCache.diagLog.debug(
                    "axBoundsCapture: duplicate crop rect \(cropRect) for " +
                        "\(item.logString); clearing both items for app-icon fallback"
                )
                result.captured.removeValue(forKey: priorTag)
                result.invalidatedTags.insert(priorTag)
                result.unconditionallyInvalidatedTags.insert(priorTag)
                result.unreadable.append(item)
                result.invalidatedTags.insert(item.tag)
                result.unconditionallyInvalidatedTags.insert(item.tag)
                continue
            }

            guard !cropRect.isNull, !cropRect.isEmpty, let rawCroppedImage = composite.cropping(to: cropRect) else {
                MenuBarItemImageCache.diagLog.debug(
                    "axBoundsCapture: cropping failed for \(item.logString) " +
                        "rawCropRect=\(mapping.raw) clamped=\(cropRect)"
                )
                result.failedCaptureItems.append(item)
                result.unreadable.append(item)
                continue
            }

            // Display-strip crops include bar fill and wallpaper, so knock out
            // the edge color. A nil knock-out (busy wallpaper) is a failed
            // capture; storing the raw crop would cache the wallpaper.
            let croppedImage: CGImage
            CaptureDiagnostics.record(rawCroppedImage, item: item, bounds: bounds, source: sourceLabel)
            if source != .displayStrip, rawCroppedImage.hasOpaquePerimeter() {
                // Opaque means SkyLight's blank slab or a glyph on a solid bar;
                // the knock-out tells them apart, the strip takes the rest.
                let separated = rawCroppedImage.separatedFromNearUniformBackground()
                guard separated.presence == .present,
                      let cleaned = separated.image
                else {
                    MenuBarItemImageCache.diagLog.debug(
                        "axBoundsCapture: opaque \(sourceLabel) crop for \(item.logString) reads " +
                            "\(String(describing: separated.presence)); leaving it to the display strip"
                    )
                    result.unreadable.append(item)
                    result.invalidatedTags.insert(item.tag)
                    continue
                }
                croppedImage = cleaned
            } else if knockOutBackground {
                guard let cleaned = rawCroppedImage.knockingOutNearUniformBackground() else {
                    MenuBarItemImageCache.diagLog.debug(
                        "axBoundsCapture: could not separate \(item.logString) from the menu bar " +
                            "background; clearing prior image for app-icon fallback"
                    )
                    result.unreadable.append(item)
                    result.invalidatedTags.insert(item.tag)
                    continue
                }
                croppedImage = cleaned // already a fresh makeImage(), do not detach again
            } else {
                croppedImage = rawCroppedImage.detachedCopy()
            }

            CaptureDiagnostics.recordCleaned(croppedImage, item: item, source: sourceLabel)

            // A crop larger than the item's frame carries a neighbour's pixels.
            // Invalidating clears a blank prior but keeps a settled one.
            guard Self.isCropWithinItemBounds(
                imageWidth: croppedImage.width,
                imageHeight: croppedImage.height,
                itemBounds: bounds,
                scale: scale
            ) else {
                MenuBarItemImageCache.diagLog.debug(
                    "axBoundsCapture: \(item.logString) \(sourceLabel) crop " +
                        "\(croppedImage.width)×\(croppedImage.height)px exceeds its bounds " +
                        "\(bounds.debugDescription); discarding crop"
                )
                result.unreadable.append(item)
                result.invalidatedTags.insert(item.tag)
                continue
            }

            // An opaque border is the blank slab SkyLight answers with for a window
            // it is not compositing. Invalidating clears a blank prior, keeps a settled one.
            guard !croppedImage.hasOpaquePerimeter() else {
                MenuBarItemImageCache.diagLog.debug(
                    "axBoundsCapture: opaque-border \(sourceLabel) crop for \(item.logString); discarding crop"
                )
                result.unreadable.append(item)
                result.invalidatedTags.insert(item.tag)
                continue
            }

            guard !croppedImage.isTransparent(alphaThreshold: 0.05) else {
                // These render blank briefly during a reflow. A recorded failure
                // would blacklist them for 30 s, so keep the last good image.
                if item.tag.isHidingUnsupported || item.tag.isNonConcealableSystemItem {
                    MenuBarItemImageCache.diagLog.debug(
                        "axBoundsCapture: blank image for reflow-transient \(item.logString); " +
                            "skipping without failure (will recover on next refresh)"
                    )
                    result.unreadable.append(item)
                    continue
                }
                // Anything reaching here is on-screen. Clear the prior, which may
                // be a stale crop from bad geometry.
                MenuBarItemImageCache.diagLog.debug(
                    "axBoundsCapture: blank image for \(item.logString); " +
                        "clearing prior image for app-icon fallback"
                )
                result.unreadable.append(item)
                result.invalidatedTags.insert(item.tag)
                continue
            }

            let captured = MenuBarItemGlyphCapture(cgImage: croppedImage, scale: scale)

            // On macOS 27 items collapsed into the overflow chevron keep AX
            // bounds over it, giving a narrow crop of the chevron that passes
            // every check above.
            if bounds.width < Self.minimumTrustedGlyphWidth, !item.tag.isLayoutAnchoredSystemItem {
                MenuBarItemImageCache.diagLog.debug(
                    "axBoundsCapture: rejecting suspiciously narrow crop " +
                        "(\(bounds.width)pt) for \(item.logString); likely overflow chevron bleed"
                )
                result.unreadable.append(item)
                result.invalidatedTags.insert(item.tag)
                continue
            }

            result.recoveredItems.append(item)
            cropRectOwners[cropRect] = item.tag
            result.captured[item.tag] = captured
        }
    }

    @concurrent
    nonisolated func captureImages(
        of items: [MenuBarItem],
        scale: CGFloat,
        appState: AppState,
        freshBounds: Bool = false,
        concealedIdentifiers: Set<String> = [],
        forgivenTags: Set<MenuBarItemTag> = [],
        geometryOwners: Set<pid_t> = []
    ) async -> CapturePass {
        // Dividers capture as transparent; the visible Thaw icon crops from the
        // display strip like any Liquid Glass item. The recording indicator is
        // excluded because capturing it shows it, which triggers a recapture.
        let capturable = items.filter {
            (!$0.isControlItem || $0.tag == .visibleControlItem)
                && !$0.isTransientControlCenterItem
                && !$0.tag.isCaptureActivityIndicator
        }

        // A bar mid-reflow draws items scaled down and faded. Bounded so a
        // flag that never clears cannot starve capture.
        let reflowSkip = await MainActor.run { () -> Int in
            let reflowing = appState.menuBarManager.shouldSuppressMenuBarAgentNudge
                || appState.menuBarManager.isRevealHideTransitionActive
            guard reflowing, consecutiveReflowSkips < Self.maximumReflowSkips else {
                consecutiveReflowSkips = 0
                return 0
            }
            consecutiveReflowSkips += 1
            return consecutiveReflowSkips
        }
        if reflowSkip > 0 {
            MenuBarItemImageCache.diagLog.debug(
                "captureImages: skipping pass (\(reflowSkip)/\(Self.maximumReflowSkips)); " +
                    "reveal/hide reflow still settling"
            )
            return CapturePass()
        }

        // macOS 27 items have no real CGWindowIDs, so crop AX bounds from the
        // hosting window or the display strip (Liquid Glass shreds under SCK).
        let displayID = await MainActor.run {
            Self.captureDisplayID(
                itemCacheDisplayID: appState.itemManager.itemDisplayID,
                activeMenuBarDisplayID: windowServer.activeMenuBarDisplayID(),
                mainDisplayID: CGMainDisplayID()
            )
        }
        let screenFrame = await MainActor.run {
            NSScreen.screen(for: displayID)?.frame
        }

        return await captureImages(
            of: capturable,
            scale: scale,
            displayID: displayID,
            screenFrame: screenFrame,
            freshBounds: freshBounds,
            concealedIdentifiers: concealedIdentifiers,
            forgivenTags: forgivenTags,
            using: LiveMenuBarCaptureReader(geometryOwners: geometryOwners)
        )
    }

    @concurrent
    nonisolated func captureImages(
        of items: [MenuBarItem],
        scale: CGFloat,
        displayID: CGDirectDisplayID,
        screenFrame: CGRect?,
        freshBounds: Bool,
        concealedIdentifiers: Set<String>,
        forgivenTags: Set<MenuBarItemTag> = [],
        using reader: any MenuBarCaptureReading = LiveMenuBarCaptureReader()
    ) async -> CapturePass {
        guard !screenIsLocked(), !Task.isCancelled else { return CapturePass() }
        let liveBoundsByID: [String: CGRect]
        if freshBounds {
            let liveItems = await reader.menuBarItems(displayID: displayID)
            guard !screenIsLocked(), !Task.isCancelled else { return CapturePass() }
            liveBoundsByID = Dictionary(
                liveItems.map { ($0.uniqueIdentifier, $0.bounds) },
                uniquingKeysWith: { first, _ in first }
            )
        } else {
            liveBoundsByID = [:]
        }

        let axItems = Self.captureBounds(
            for: items,
            freshBounds: freshBounds,
            liveBoundsByID: liveBoundsByID,
            screenFrame: screenFrame
        )

        guard !axItems.isEmpty else {
            MenuBarItemImageCache.diagLog.debug(
                "captureImages: no on-screen items to capture for this section (macOS 27)"
            )
            return CapturePass()
        }

        return await axBoundsCapture(
            axItems,
            scale: scale,
            displayID: displayID,
            validateFreshBounds: freshBounds,
            concealedIdentifiers: concealedIdentifiers,
            forgivenTags: forgivenTags,
            using: reader
        )
    }

    /// Who is going to look at the pixels a pass is about to read.
    ///
    /// Gathered on the main actor once per pass.
    struct CaptureDemand {
        /// The state of "Use app icons instead of live previews".
        let usesAppIcons: Bool
        /// Whether search or the item hotkey list is up. Both read captures
        /// directly and ignore the app-icon preference.
        let hasUnfilteredConsumer: Bool
        /// Items the alert-reveal watcher compares capture to capture, so they
        /// are captured whatever the preference says.
        let alertRevealIdentifiers: Set<String>
    }

    @MainActor
    private func captureDemand() -> CaptureDemand {
        let nav = makeNavigationStateSnapshot()
        return CaptureDemand(
            usesAppIcons: configuration.alwaysUseAppIconForMenuBarItems,
            hasUnfilteredConsumer: nav.isSearchPresented || nav.isItemHotkeyListExpanded,
            alertRevealIdentifiers: MenuBarItemAlertReveals.identifiers()
        )
    }

    /// Narrows a section's items to the ones some surface will actually draw.
    ///
    /// With the app-icon preference on, only Apple's modules (no per-module
    /// icon) and items with no usable app icon still need captures.
    static nonisolated func itemsNeedingCapture(
        _ items: [MenuBarItem],
        demand: CaptureDemand
    ) -> [MenuBarItem] {
        guard demand.usesAppIcons, !demand.hasUnfilteredConsumer else {
            return items
        }
        return items.filter { item in
            OverflowFallbackIcon.usesCapturedSystemPreview(item)
                || !OverflowFallbackIcon.canRenderAppIconWithoutCapture(for: item)
                || demand.alertRevealIdentifiers.contains(item.tag.tagIdentifier)
        }
    }

    /// Captures the images of the menu bar items in the given section.
    func captureImages(
        for section: MenuBarSection.Name,
        scale: CGFloat,
        appState: AppState
    ) async -> CapturePass {
        let items = Self.itemsNeedingCapture(
            appState.itemManager.managedItems(for: section),
            demand: captureDemand()
        )
        guard !items.isEmpty else {
            return CapturePass()
        }
        let revealedSection = appState.menuBarManager.sectionController.revealedSection
        let shouldUseFreshBounds = Self.shouldUseFreshBounds(
            for: section,
            revealedSection: revealedSection
        )
        // A reveal just put these back on the bar, so they get a fresh attempt
        // whatever their record says. The pass only sets the record aside; it is
        // forgotten when the pass commits, so a discarded pass forgives nothing.
        let forgivenTags = section != .visible && shouldUseFreshBounds
            ? Set(items.map(\.tag))
            : []
        // A stale item cache can let concealed items into this pass; the crop
        // loop rejects them against this set.
        let concealedIdentifiers = appState.menuBarManager.sectionController
            .effectivelyConcealedIdentifiers
        let captureResult = await captureImages(
            of: items,
            scale: scale,
            appState: appState,
            // Re-read geometry before the screenshot, including visible items;
            // the post-capture ownership check still rejects movement or ambiguity.
            freshBounds: shouldUseFreshBounds,
            concealedIdentifiers: concealedIdentifiers,
            forgivenTags: forgivenTags,
            geometryOwners: Self.captureGeometryOwners(
                for: items,
                knownItems: appState.itemManager.managedItems,
                recentItems: appState.itemManager.onScreenItemSnapshot.items
            )
        )
        if !captureResult.unreadable.isEmpty {
            MenuBarItemImageCache.diagLog.debug(
                "captureImages: \(captureResult.unreadable.count) items failed capture"
            )
        }
        return captureResult
    }
}
