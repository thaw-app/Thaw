//
//  MenuBarItemImageCache+Capture.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import os.lock

extension MenuBarItemImageCache {
    private struct CaptureResult {
        var images = [MenuBarItemTag: CapturedImage]()

        /// The menu bar items excluded from the capture.
        var excluded = [MenuBarItem]()
    }

    /// Immutable input for a capture-helper batch that is safe to transfer
    /// from the main actor to the concurrent executor.
    private nonisolated struct IdentifierCaptureRequest: Sendable {
        let identifier: String
        let windowID: CGWindowID
    }

    // MARK: Capturing Images

    /// Captures a composite image of the given items and crops out each one.
    ///
    /// Takes pre-fetched bounds to avoid a TOCTOU race between lookup and capture.
    /// Items must be on-screen; the caller filters the rest.
    private nonisolated func compositeCapture(
        _ itemsWithBounds: [(item: MenuBarItem, bounds: CGRect)],
        scale: CGFloat
    ) async -> CaptureResult {
        var result = CaptureResult()

        var windowIDs = [CGWindowID]()
        var storage = [CGWindowID: (MenuBarItem, CGRect)]()
        var boundsUnion = CGRect.null

        for (item, bounds) in itemsWithBounds {
            // A degenerate window corrupts the slice geometry and the union width
            // that resolvedScale reads (#990).
            guard Self.isCapturableBounds(bounds) else {
                MenuBarItemImageCache.diagLog.debug(
                    "compositeCapture: skipping degenerate bounds for \(item.logString) (\(bounds.width)x\(bounds.height))"
                )
                result.excluded.append(item)
                continue
            }
            windowIDs.append(item.windowID)
            storage[item.windowID] = (item, bounds)
            boundsUnion = boundsUnion.union(bounds)
        }

        guard !windowIDs.isEmpty else {
            return result
        }

        let compositeImage = await ScreenCapture.captureWindowsAsync(
            with: windowIDs,
            option: captureOption
        )

        guard let compositeImage else {
            MenuBarItemImageCache.diagLog.warning("compositeCapture: ScreenCapture.captureWindows returned nil for \(windowIDs.count) windows")
            result.excluded = itemsWithBounds.map(\.item)
            return result
        }

        // SCK picks the scale of whichever display owns the filter, which on
        // mixed-scale setups may not be the one passed in (#990). Read it from the capture.
        guard let effectiveScale = MenuBarItemImageCache.resolvedScale(
            imagePixelWidth: compositeImage.width,
            boundsWidth: boundsUnion.width,
            expected: scale
        ) else {
            MenuBarItemImageCache.diagLog.warning(
                "compositeCapture: implausible scale — \(compositeImage.width)px wide for a \(boundsUnion.width)pt union at expected scale \(scale), excluding \(windowIDs.count) windows"
            )
            result.excluded = itemsWithBounds.map(\.item)
            return result
        }
        if effectiveScale != scale {
            MenuBarItemImageCache.diagLog.warning(
                "compositeCapture: capture scale \(effectiveScale) differs from display scale \(scale); using the captured scale"
            )
        }

        guard !compositeImage.isTransparent() else {
            MenuBarItemImageCache.diagLog.warning("compositeCapture: composite image is fully transparent (\(compositeImage.width)x\(compositeImage.height)) — screen recording permission may not be effective")
            result.excluded = itemsWithBounds.map(\.item)
            return result
        }

        MenuBarItemImageCache.diagLog.debug(
            "compositeCapture: composite image OK (\(compositeImage.width)x\(compositeImage.height)), cropping \(windowIDs.count) items"
        )

        var cropSuccessCount = 0
        var cropNilCount = 0
        var cropTransparentCount = 0
        for windowID in windowIDs {
            guard let (item, bounds) = storage[windowID] else {
                continue
            }

            if shouldSkipCapture(for: item) {
                MenuBarItemImageCache.diagLog.debug(
                    "Skipping composite capture for repeatedly failing item: \(item.logString)"
                )
                result.excluded.append(item)
                continue
            }

            let cropRect = CGRect(
                x: (bounds.origin.x - boundsUnion.origin.x) * effectiveScale,
                y: (bounds.origin.y - boundsUnion.origin.y) * effectiveScale,
                width: bounds.width * effectiveScale,
                height: bounds.height * effectiveScale
            )

            let croppedImage = compositeImage.cropping(to: cropRect)?.detachedCopy()
            guard let croppedImage else {
                cropNilCount += 1
                recordCaptureFailure(for: item)
                result.excluded.append(item)
                continue
            }
            guard !croppedImage.isTransparent() else {
                cropTransparentCount += 1
                recordCaptureFailure(for: item)
                result.excluded.append(item)
                continue
            }

            cropSuccessCount += 1
            recordCaptureSuccess(for: item)
            result.images[item.tag] = CapturedImage(
                cgImage: croppedImage,
                scale: effectiveScale
            )
        }

        MenuBarItemImageCache.diagLog.debug(
            "compositeCapture: crops done — \(cropSuccessCount) ok, \(cropNilCount) nil, \(cropTransparentCount) transparent"
        )

        return result
    }

    /// The scale a captured image was actually taken at, or nil when the
    /// image cannot be trusted at any scale.
    ///
    /// Pixel width over point width is the real capture scale; when it
    /// disagrees with `expected`, it wins, since SCK may have chosen another display.
    ///
    /// A derived scale off every real backing scale means stale bounds, so drop
    /// the item: a missing icon recovers, a wrongly-scaled one gets cached.
    ///
    /// - Parameters:
    ///   - imagePixelWidth: Width of the captured image, in pixels.
    ///   - boundsWidth: Width of the item's window, in points.
    ///   - expected: The scale of the display resolved for the menu bar.
    static nonisolated func resolvedScale(
        imagePixelWidth: Int,
        boundsWidth: CGFloat,
        expected: CGFloat
    ) -> CGFloat? {
        guard boundsWidth > 0, imagePixelWidth > 0, expected > 0 else {
            return nil
        }

        let derived = CGFloat(imagePixelWidth) / boundsWidth

        // Integer pixel widths make narrow items noisy.
        if abs(derived - expected) <= scaleTolerance {
            return expected
        }

        // Anything off a real backing scale is bad input, not a mismatch.
        return plausibleBackingScales.first { abs(derived - $0) <= scaleTolerance }
    }

    /// Backing scale factors macOS actually reports for a display.
    private static nonisolated let plausibleBackingScales: [CGFloat] = [1, 2, 3]

    /// How far a derived scale may sit from a candidate before it stops
    /// counting as that scale.
    private static nonisolated let scaleTolerance: CGFloat = 0.05

    private nonisolated func individualCapture(
        _ items: [MenuBarItem],
        scale: CGFloat
    ) async -> CaptureResult {
        var result = CaptureResult()
        var capturedCount = 0
        var nilImageCount = 0
        var transparentCount = 0
        var skippedCount = 0

        for item in items {
            if shouldSkipCapture(for: item) {
                MenuBarItemImageCache.diagLog.debug(
                    "Skipping capture for repeatedly failing item: \(item.logString)"
                )
                skippedCount += 1
                result.excluded.append(item)
                continue
            }

            let image = await ScreenCapture.captureWindowAsync(
                with: item.windowID,
                option: captureOption
            )

            guard let image else {
                MenuBarItemImageCache.diagLog.debug("individualCapture: captureWindow returned nil for \(item.logString)")
                nilImageCount += 1
                recordCaptureFailure(for: item)
                result.excluded.append(item)
                continue
            }

            guard !image.isTransparent() else {
                MenuBarItemImageCache.diagLog.debug("individualCapture: captured image is transparent for \(item.logString) (\(image.width)x\(image.height))")
                transparentCount += 1
                recordCaptureFailure(for: item)
                result.excluded.append(item)
                continue
            }

            // SCK captures at the scale of the display it picks by frame intersection.
            // On mixed-scale setups a wrong scale doubles the icon's size (#851).
            guard let resolvedScale = MenuBarItemImageCache.resolvedScale(
                imagePixelWidth: image.width,
                boundsWidth: item.bounds.width,
                expected: scale
            ) else {
                MenuBarItemImageCache.diagLog.warning(
                    "individualCapture: implausible scale for \(item.logString) — \(image.width)px wide for bounds width \(item.bounds.width) at expected scale \(scale), excluding"
                )
                recordCaptureFailure(for: item)
                result.excluded.append(item)
                continue
            }

            if resolvedScale != scale {
                MenuBarItemImageCache.diagLog.warning(
                    "individualCapture: capture scale \(resolvedScale) differs from display scale \(scale) for \(item.logString); using the captured scale"
                )
            }

            capturedCount += 1
            recordCaptureSuccess(for: item)
            result.images[item.tag] = CapturedImage(
                cgImage: image,
                scale: resolvedScale
            )
        }

        MenuBarItemImageCache.diagLog.debug("individualCapture: \(items.count) items -> \(capturedCount) captured, \(nilImageCount) nil, \(transparentCount) transparent, \(skippedCount) skipped (blacklisted)")
        return result
    }

    /// Captures the images of the given menu bar items and returns the result.
    private nonisolated func captureImages(
        of items: [MenuBarItem],
        scale: CGFloat,
        appState: AppState
    ) async -> CaptureResult {
        // Our control items always capture transparent; skip them to avoid an
        // endless fail/blacklist/retry cycle.
        let capturable = items.filter { !$0.isControlItem }

        // Composite capture doesn't handle the overlaps a move can leave.
        if await appState.itemManager.lastMoveOperationOccurred(
            within: .seconds(2)
        ) {
            MenuBarItemImageCache.diagLog.debug("Capturing individually due to recent item movement")
            return await individualCapture(capturable, scale: scale)
        }

        // Off-screen items inflate boundsUnion and fail the whole composite on
        // width. refreshImages captures them instead.
        // isWindowOnScreen() can't be used: macOS reports hidden items as on-screen.
        let displayID = Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
        let screenFrame = await MainActor.run {
            NSScreen.screens.first { $0.displayID == displayID }?.frame
        }

        // One bounds fetch for both the filter and compositeCapture avoids a TOCTOU race.
        var onScreenItemsWithBounds: [(item: MenuBarItem, bounds: CGRect)] = []
        var offScreenCount = 0
        var nilBoundsCount = 0

        for item in capturable {
            guard let bounds = Bridging.getWindowBounds(for: item.windowID) else {
                // No capture path works without bounds.
                nilBoundsCount += 1
                continue
            }
            if let screenFrame, !screenFrame.intersects(bounds) {
                offScreenCount += 1
            } else {
                onScreenItemsWithBounds.append((item: item, bounds: bounds))
            }
        }

        if nilBoundsCount > 0 {
            MenuBarItemImageCache.diagLog.debug(
                "captureImages: \(nilBoundsCount)/\(capturable.count) items had no bounds, skipped"
            )
        }
        if offScreenCount > 0 {
            MenuBarItemImageCache.diagLog.debug(
                "captureImages: \(offScreenCount)/\(capturable.count) off-screen items skipped (live refresh handles them)"
            )
        }

        guard !onScreenItemsWithBounds.isEmpty else {
            MenuBarItemImageCache.diagLog.debug(
                "captureImages: no on-screen items to capture for this section"
            )
            return CaptureResult()
        }

        let compositeResult = await compositeCapture(onScreenItemsWithBounds, scale: scale)

        if compositeResult.excluded.isEmpty {
            return compositeResult // All items captured successfully.
        }

        MenuBarItemImageCache.diagLog.debug(
            "\(compositeResult.excluded.count)/\(onScreenItemsWithBounds.count) items excluded from composite, retrying individually"
        )

        var individualResult = await individualCapture(
            compositeResult.excluded,
            scale: scale
        )

        // Keep excluded items so they can be logged elsewhere.
        individualResult.images.merge(compositeResult.images) { _, new in new }

        return individualResult
    }

    /// Lightweight image refresh for the IceBar.
    ///
    /// One composite capture, cropped per item. Updates LRU order but skips
    /// eviction, failure tracking, and cleanup, and skips unchanged images.
    ///
    /// @concurrent because nonisolated alone stays on the caller's actor
    /// (SE-0461), which would put the capture work on the main thread.
    @concurrent
    nonisolated func refreshImages(
        of items: [MenuBarItem],
        scale: CGFloat,
        viaSCK: Bool = false
    ) async {
        if !viaSCK {
            await refreshImagesFromCaptureService(items: items, scale: scale)
            return
        }

        var windowIDs = [CGWindowID]()
        var storage = [CGWindowID: (MenuBarItem, CGRect)]()
        var boundsUnion = CGRect.null

        for item in items {
            guard let bounds = Bridging.getWindowBounds(for: item.windowID) else {
                continue
            }
            // A degenerate window parked off-screen stretches boundsUnion across
            // the gap, and the width check then discards every batch.
            guard Self.isCapturableBounds(bounds) else {
                MenuBarItemImageCache.diagLog.debug(
                    "refreshImages: skipping degenerate bounds for \(item.logString) (\(bounds.width)x\(bounds.height))"
                )
                continue
            }
            windowIDs.append(item.windowID)
            storage[item.windowID] = (item, bounds)
            boundsUnion = boundsUnion.union(bounds)
        }

        guard !windowIDs.isEmpty else {
            MenuBarItemImageCache.diagLog.debug("refreshImages: no items with bounds, skipping")
            return
        }

        // SCK is leak-free but display-bounded, so only for on-screen items.
        let compositeImage = await ScreenCapture.captureWindowsAsync(
            with: windowIDs,
            option: captureOption
        )
        guard let compositeImage else {
            MenuBarItemImageCache.diagLog.debug("refreshImages: capture failed, skipping")
            return
        }

        // A 2x capture of a 1x display is a good image, not a mismatch (#990).
        guard let effectiveScale = MenuBarItemImageCache.resolvedScale(
            imagePixelWidth: compositeImage.width,
            boundsWidth: boundsUnion.width,
            expected: scale
        ) else {
            MenuBarItemImageCache.diagLog.debug(
                "refreshImages: implausible scale (\(compositeImage.width)px for a \(boundsUnion.width)pt union at expected scale \(scale)), skipping"
            )
            return
        }
        if effectiveScale != scale {
            MenuBarItemImageCache.diagLog.debug(
                "refreshImages: capture scale \(effectiveScale) differs from display scale \(scale); using the captured scale"
            )
        }

        guard !compositeImage.isTransparent() else {
            MenuBarItemImageCache.diagLog.debug("refreshImages: composite is transparent, skipping")
            return
        }

        var newImages = [MenuBarItemTag: CapturedImage]()
        for windowID in windowIDs {
            guard let (item, bounds) = storage[windowID] else { continue }
            let cropRect = CGRect(
                x: (bounds.origin.x - boundsUnion.origin.x) * effectiveScale,
                y: (bounds.origin.y - boundsUnion.origin.y) * effectiveScale,
                width: bounds.width * effectiveScale,
                height: bounds.height * effectiveScale
            )
            // No per-item transparency check: transparent crops are spacers.
            guard let image = compositeImage.cropping(to: cropRect)?.detachedCopy() else {
                continue
            }
            newImages[item.tag] = CapturedImage(cgImage: image, scale: effectiveScale)
        }

        guard !newImages.isEmpty, !Task.isCancelled else { return }
        await applyRefreshedImages(newImages)
    }

    /// Offscreen items go through the recyclable SkyLight helper so the
    /// per-call dictionary leak stays out of the UI process.
    private nonisolated func refreshImagesFromCaptureService(
        items: [MenuBarItem],
        scale: CGFloat
    ) async {
        let windowIDs = items.map(\.windowID)
        guard !windowIDs.isEmpty else { return }
        var storage = [CGWindowID: MenuBarItem]()
        for item in items {
            storage[item.windowID] = item
        }
        let frames = await MenuBarCaptureService.Connection.shared.capture(
            windowIDs: windowIDs,
            scale: scale,
            option: captureOption
        )
        guard !frames.isEmpty, !Task.isCancelled else { return }

        var newImages = [MenuBarItemTag: CapturedImage]()
        for frame in frames {
            guard let item = storage[frame.windowID],
                  let image = MenuBarCaptureService.makeImage(from: frame)
            else { continue }
            newImages[item.tag] = CapturedImage(cgImage: image, scale: CGFloat(frame.scale))
        }
        guard !newImages.isEmpty, !Task.isCancelled else { return }
        await applyRefreshedImages(newImages)
    }

    /// Captures a fresh batch for image-comparison triggers via the helper process.
    func captureCurrentImages(
        forItemIdentifiers identifiers: Set<String>
    ) async -> [String: CGImage] {
        guard let appState, !identifiers.isEmpty else { return [:] }

        let requests: [IdentifierCaptureRequest] = appState.itemManager.itemCache.managedItems.compactMap { item in
            let identifier = item.tag.tagIdentifier
            guard identifiers.contains(identifier) else { return nil }
            return IdentifierCaptureRequest(identifier: identifier, windowID: item.windowID)
        }
        guard !requests.isEmpty else { return [:] }

        let preferredDisplayID = appState.itemManager.itemCache.displayID
        guard let screen = Self.resolveScreen(preferredDisplayID: preferredDisplayID) else {
            return [:]
        }

        do {
            try await captureSemaphore.wait()
        } catch {
            return [:]
        }
        let captured = await Self.captureCurrentImages(
            requests: requests,
            scale: screen.screen.backingScaleFactor,
            option: captureOption
        )
        await captureSemaphore.signal()
        return captured
    }

    @concurrent
    private static nonisolated func captureCurrentImages(
        requests: [IdentifierCaptureRequest],
        scale: CGFloat,
        option: CGWindowImageOption
    ) async -> [String: CGImage] {
        let frames = await MenuBarCaptureService.Connection.shared.capture(
            windowIDs: requests.map(\.windowID),
            scale: scale,
            option: option
        )
        guard !frames.isEmpty, !Task.isCancelled else { return [:] }

        let identifierByWindowID = Dictionary(
            requests.map { ($0.windowID, $0.identifier) },
            uniquingKeysWith: { first, _ in first }
        )
        var images = [String: CGImage]()
        for frame in frames {
            guard let identifier = identifierByWindowID[frame.windowID],
                  let image = MenuBarCaptureService.makeImage(from: frame)
            else { continue }
            images[identifier] = image
        }
        return images
    }

    private func applyRefreshedImages(_ newImages: [MenuBarItemTag: CapturedImage]) {
        var updatedCount = 0
        for (tag, newImage) in newImages where !CapturedImage.isVisuallyEqual(images[tag], newImage) {
            images[tag] = newImage
            updateAccessOrder(for: tag)
            updatedCount += 1
        }
        // Record unchanged captures too: steady samples are what age a blink out.
        recordForAttention(newImages)
        if updatedCount > 0 {
            MenuBarItemImageCache.diagLog.debug(
                "refreshImages: ✓ updated \(updatedCount)/\(newImages.count) items (visually changed)"
            )
        }
    }

    /// Feeds a batch of captures to the attention detector and republishes
    /// the verdict when it changes.
    private func recordForAttention(_ newImages: [MenuBarItemTag: CapturedImage]) {
        let globalAttentionDetection = Defaults.bool(forKey: .surfaceItemsSeekingAttention)
        guard globalAttentionDetection || !attentionDetectionItemIdentifiers.isEmpty else {
            if !tagsSeekingAttention.isEmpty {
                tagsSeekingAttention = []
            }
            return
        }

        let detectionTags = globalAttentionDetection
            ? Set(images.keys)
            : Set(images.keys.filter {
                attentionDetectionItemIdentifiers.contains($0.tagIdentifier)
            })
        let now = Date.timeIntervalSinceReferenceDate
        for (tag, image) in newImages where detectionTags.contains(tag) {
            attentionDetector.record(fingerprint: image.fingerprint, for: tag, at: now)
        }
        attentionDetector.retain(detectionTags)

        let seeking = Set(detectionTags.filter { attentionDetector.isSeekingAttention($0, at: now) })
        guard seeking != tagsSeekingAttention else { return }
        tagsSeekingAttention = seeking
        if !seeking.isEmpty {
            MenuBarItemImageCache.diagLog.debug(
                "attention: \(seeking.count) item(s) seeking attention"
            )
        }
    }

    /// Clears an item's recorded history, so surfacing it does not
    /// immediately re-trigger on the blink that surfaced it.
    func clearAttention(for tag: MenuBarItemTag) {
        attentionDetector.reset(tag)
        tagsSeekingAttention.remove(tag)
    }

    func captureImages(
        for section: MenuBarSection.Name,
        scale: CGFloat,
        appState: AppState
    ) async -> [MenuBarItemTag: CapturedImage] {
        let items = appState.itemManager.itemCache.managedItems(
            for: section
        )
        let captureResult = await captureImages(
            of: items,
            scale: scale,
            appState: appState
        )
        if !captureResult.excluded.isEmpty {
            MenuBarItemImageCache.diagLog.debug(
                "captureImages: \(captureResult.excluded.count) items failed capture"
            )
        }
        return captureResult.images
    }

    // MARK: Failed Capture Management

    private nonisolated func shouldSkipCapture(for item: MenuBarItem) -> Bool {
        failedCapturesLock.withLock { dict in
            guard let failed = dict[item.tag] else {
                return false
            }

            if failed.failureCount >= Self.maxFailuresBeforeBlacklist {
                let timeSinceFailure = Date().timeIntervalSince(
                    failed.lastFailureTime
                )
                if timeSinceFailure < Self.blacklistCooldownSeconds {
                    return true
                } else {
                    dict.removeValue(forKey: item.tag)
                    return false
                }
            }

            return false
        }
    }

    private nonisolated func recordCaptureFailure(for item: MenuBarItem) {
        let now = Date()
        failedCapturesLock.withLock { dict in
            let existing = dict[item.tag]

            if let existing {
                let newCount = existing.failureCount + 1
                dict[item.tag] = FailedCapture(
                    tag: item.tag,
                    failureCount: newCount,
                    lastFailureTime: now
                )

                if newCount == Self.maxFailuresBeforeBlacklist {
                    MenuBarItemImageCache.diagLog.info(
                        "Item blacklisted after \(newCount) failures: \(item.logString) (will retry after \(Self.blacklistCooldownSeconds)s cooldown)"
                    )
                }
            } else {
                dict[item.tag] = FailedCapture(
                    tag: item.tag,
                    failureCount: 1,
                    lastFailureTime: now
                )
            }

            let cutoff = now.addingTimeInterval(-Self.blacklistCooldownSeconds)
            dict = dict.filter { _, failed in
                failed.lastFailureTime > cutoff
            }
        }
    }

    private nonisolated func recordCaptureSuccess(for item: MenuBarItem) {
        let recovered = failedCapturesLock.withLock { dict in
            dict.removeValue(forKey: item.tag)
        }
        if let existing = recovered, existing.failureCount >= 2 {
            MenuBarItemImageCache.diagLog.info(
                "Item recovered after \(existing.failureCount) previous failures: \(item.logString)"
            )
        }
    }
}
