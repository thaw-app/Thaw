//
//  AXBoundsCropper.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import os
import ThawCapture

/// Crops status-item glyphs by their Accessibility bounds from the hosting window, an owner's bar window or the display strip.
/// It never writes the failure ledger; the skip closure is its only view of it.
nonisolated struct AXBoundsCropper: Sendable {
    typealias CapturePass = MenuBarItemImageCache.CapturePass

    /// How a crop of cached items treats them.
    struct Options {
        /// Re-read item geometry before the screenshot and check it again afterward.
        var freshBounds = false
        var concealedIdentifiers: Set<String> = []
        /// Items captured even though they would normally be skipped.
        var forgivenTags: Set<MenuBarItemTag> = []
    }

    /// Items with the bounds to cut them at, and how far to trust those bounds.
    struct Request: Sendable {
        var items: [(item: MenuBarItem, bounds: CGRect)]
        var displayID: CGDirectDisplayID
        var validateFreshBounds = false
        var concealedIdentifiers: Set<String> = []
        var forgivenTags: Set<MenuBarItemTag> = []
    }

    private static let diagLog = MenuBarItemImageCache.diagLog

    let screenIsLocked: @Sendable () -> Bool
    /// Whether a capture asked for now would run; false while no Thaw surface is open.
    let captureIsAllowed: @Sendable () -> Bool
    /// Displays whose hosting-window capture already failed since it last
    /// succeeded, so the repeats log at debug instead of warning.
    fileprivate let hostingFailureWarnedDisplays = OSAllocatedUnfairLock<Set<CGDirectDisplayID>>(initialState: [])

    /// Crops cached items, re-reading their positions first when options ask for fresh bounds.
    /// Items whose bounds miss screenFrame horizontally are left out.
    @concurrent
    func crop(
        _ items: [MenuBarItem],
        on displayID: CGDirectDisplayID,
        screenFrame: CGRect?,
        options: Options,
        using reader: any MenuBarCaptureReading,
        skipping shouldSkip: @escaping @Sendable (MenuBarItem) -> Bool
    ) async -> CapturePass {
        guard !screenIsLocked(), !Task.isCancelled else { return CapturePass() }
        let liveBoundsByID: [String: CGRect]
        if options.freshBounds {
            let liveItems = await reader.menuBarItems(displayID: displayID)
            guard !screenIsLocked(), !Task.isCancelled else { return CapturePass() }
            liveBoundsByID = Dictionary(
                liveItems.map { ($0.uniqueIdentifier, $0.bounds) },
                uniquingKeysWith: { first, _ in first }
            )
        } else {
            liveBoundsByID = [:]
        }

        let axItems = MenuBarItemImageCache.captureBounds(
            for: items,
            freshBounds: options.freshBounds,
            liveBoundsByID: liveBoundsByID,
            screenFrame: screenFrame
        )

        guard !axItems.isEmpty else {
            Self.diagLog.debug("captureImages: no on-screen items to capture for this section (macOS 27)")
            return CapturePass()
        }

        let request = Request(
            items: axItems,
            displayID: displayID,
            validateFreshBounds: options.freshBounds,
            concealedIdentifiers: options.concealedIdentifiers,
            forgivenTags: options.forgivenTags
        )
        return await crop(request, using: reader, skipping: shouldSkip)
    }

    /// Crops the request's items at the bounds it gives. A screen lock at any point discards the whole
    /// pass; cancellation keeps the crops already made and starts no further source.
    @concurrent
    func crop(
        _ request: Request,
        using reader: any MenuBarCaptureReading,
        skipping shouldSkip: @escaping @Sendable (MenuBarItem) -> Bool
    ) async -> CapturePass {
        guard !screenIsLocked(), !request.items.isEmpty else { return CapturePass() }
        let band = await reader.captureBand(displayID: request.displayID)
        guard !screenIsLocked() else { return CapturePass() }
        let overflowBounds = await reader.overflowBounds(displayID: request.displayID)
        guard !screenIsLocked() else { return CapturePass() }
        var pass = CapturePass()
        // Staged, not applied: the ledger is read-only until the pass commits.
        pass.forgivenTags = request.forgivenTags
        let (candidates, implausible) = AXCropRules.eligibleCandidates(
            request.items, band: band, overflowBounds: overflowBounds, screens: reader.displayBounds()
        )
        for item in implausible {
            pass.reject(item, .invalidate)
        }
        guard !candidates.isEmpty else {
            // Says which test failed: no app-menu edge refuses every icon, a stale edge refuses those left of it.
            Self.diagLog.debug(
                "axBoundsCapture: no trustworthy status-item bounds; skipping screenshot " +
                    "(menuMaxX=\(band.menuMaxX.map { "\($0)" } ?? "nil"), band=\(band.frame), items=" +
                    request.items.map { "\($0.item.logString)@\($0.bounds)" }.joined(separator: ", ") + ")"
            )
            return pass
        }
        var run = CropRun(
            cropper: self,
            reader: reader,
            shouldSkip: shouldSkip,
            pass: pass,
            context: CropContext(
                displayID: request.displayID,
                validateFreshBounds: request.validateFreshBounds,
                concealedIdentifiers: request.concealedIdentifiers,
                forgivenTags: request.forgivenTags,
                captureTimeBounds: Dictionary(
                    candidates.map { ($0.item.uniqueIdentifier, $0.bounds) },
                    uniquingKeysWith: { first, _ in first }
                ),
                overflowBounds: overflowBounds
            )
        )
        // Windows first: capturing the display can black out DRM video while the
        // stream runs, and reads other apps' windows this crop doesn't need.
        await run.cropWindowSources(candidates)
        guard !screenIsLocked() else { return CapturePass() }
        // A superseded pass keeps the crops it has and starts no further source.
        guard !Task.isCancelled else { return run.pass }
        // The strip is only for a bar window that couldn't be read at all. An item
        // that window didn't yield is not worth a display capture on every pass.
        let unresolved = candidates.filter { !run.pass.captured.keys.contains($0.item.tag) }
        if !run.context.hasHostingCapture, !unresolved.isEmpty {
            await run.cropStrip(unresolved)
        }
        return screenIsLocked() ? CapturePass() : run.pass
    }
}

/// The geometry one crop checks its sources against.
private nonisolated struct CropContext {
    let displayID: CGDirectDisplayID
    let validateFreshBounds: Bool
    let concealedIdentifiers: Set<String>
    let forgivenTags: Set<MenuBarItemTag>
    // Peer frames must come from the same enumeration as the crop rects,
    // not a later read that can mistake one moving item for two neighbors.
    let captureTimeBounds: [String: CGRect]
    var postCaptureBounds: [String: CGRect] = [:]
    var overflowBounds: [CGRect]
    var ambiguousIdentifiers: Set<String> = []
    var hasHostingCapture = false
}

/// One crop's walk over its sources, accumulating the pass.
private nonisolated struct CropRun {
    private static let diagLog = MenuBarItemImageCache.diagLog

    let cropper: AXBoundsCropper
    let reader: any MenuBarCaptureReading
    let shouldSkip: @Sendable (MenuBarItem) -> Bool
    var pass: AXBoundsCropper.CapturePass
    var context: CropContext
    /// Crop rectangles already published per source. Owner windows share one
    /// table, since their crops are compared across owners.
    private var claimedCropRects = [AXCropRules.CaptureSource: [CGRect: MenuBarItemTag]]()

    init(
        cropper: AXBoundsCropper,
        reader: any MenuBarCaptureReading,
        shouldSkip: @escaping @Sendable (MenuBarItem) -> Bool,
        pass: AXBoundsCropper.CapturePass,
        context: CropContext
    ) {
        self.cropper = cropper
        self.reader = reader
        self.shouldSkip = shouldSkip
        self.pass = pass
        self.context = context
    }

    private var isLocked: Bool {
        cropper.screenIsLocked()
    }

    mutating func cropWindowSources(_ candidates: [(item: MenuBarItem, bounds: CGRect)]) async {
        let hosting = await readHostingCapture(candidates)
        guard !isLocked, !Task.isCancelled else { return }
        if let hosting {
            context.hasHostingCapture = true
            // Positions read after the pixels, whatever the caller asked for: a
            // crop by a stale rectangle would hand one item another's picture.
            guard await readLiveGeometry(of: candidates) else { return }
            cropSource(candidates, capture: hosting, source: .hosting, context: context)
        }
        // Some apps draw in an owner window rather than MenuBarAgent's window.
        // A missing hosting capture must still reach this stage.
        let unresolved = candidates.filter { candidate in
            !pass.captured.keys.contains(candidate.item.tag) && Self.mayTryAnotherSource(candidate, context: context)
        }
        for ownerPID in Set(unresolved.map(\.item.ownerPID)).sorted() {
            guard !isLocked, !Task.isCancelled else { return }
            let capture = await reader.barWindowCapture(ownerPID: ownerPID, displayID: context.displayID)
            guard !isLocked else { return }
            guard let capture else { continue }
            // Each owner window is its own acquisition interval: the hosting
            // read cannot vouch for pixels taken after it.
            guard let sourceContext = await contextAfterSource() else { return }
            context.overflowBounds = sourceContext.overflowBounds
            cropSource(
                unresolved.filter { $0.item.ownerPID == ownerPID },
                capture: capture,
                source: .barWindow,
                context: sourceContext
            )
        }
    }

    mutating func cropStrip(_ candidates: [(item: MenuBarItem, bounds: CGRect)]) async {
        guard !isLocked, !candidates.isEmpty else { return }
        let capture = await reader.displayStripCapture(displayID: context.displayID)
        guard !isLocked else { return }
        guard let capture, Self.isPlausibleCapture(capture) else {
            // Cancellation makes every source answer nil; that is not a failed read.
            guard !Task.isCancelled else {
                Self.diagLog.debug("axBoundsCapture: capture superseded for \(candidates.count) items; keeping their pictures")
                return
            }
            if pass.noteMissingCapture(of: candidates.map(\.item), captureWasAllowed: cropper.captureIsAllowed()) {
                Self.diagLog.warning("axBoundsCapture: captureMenuBarDisplayStripAsync failed for \(candidates.count) items")
            } else {
                Self.diagLog.debug("axBoundsCapture: capture refused for \(candidates.count) items; no Thaw surface is open")
            }
            return
        }
        // A hosting enumeration cannot establish ownership of on-screen pixels.
        guard await readLiveGeometry(of: candidates) else { return }
        cropSource(candidates, capture: capture, source: .displayStrip, context: context)
    }

    private mutating func readHostingCapture(
        _ candidates: [(item: MenuBarItem, bounds: CGRect)]
    ) async -> ScreenCapture.MenuBarHostingCapture? {
        guard !isLocked else { return nil }
        let displayID = context.displayID
        let capture = await reader.hostingCapture(displayID: displayID)
        guard !isLocked else { return nil }
        if let capture, Self.isPlausibleCapture(capture) {
            cropper.hostingFailureWarnedDisplays.withLock { _ = $0.remove(displayID) }
            return capture
        }
        // Cancellation makes every source answer nil; that is not a failed read.
        guard !Task.isCancelled, pass.noteMissingCapture(of: candidates.map(\.item), captureWasAllowed: cropper.captureIsAllowed()) else {
            return nil
        }
        let firstFailure = cropper.hostingFailureWarnedDisplays.withLock { $0.insert(displayID).inserted }
        let message = "axBoundsCapture: captureMenuBarHostingWindowAsync failed for \(candidates.count) items"
        if firstFailure {
            Self.diagLog.warning(message)
        } else {
            Self.diagLog.debug(message)
        }
        return nil
    }

    /// Reads positions and overflow after a source's pixels. False when the screen locked meanwhile.
    private mutating func readLiveGeometry(of candidates: [(item: MenuBarItem, bounds: CGRect)]) async -> Bool {
        let live = await reader.liveBounds(for: candidates)
        guard !isLocked else { return false }
        context.postCaptureBounds = live.bounds
        context.ambiguousIdentifiers = live.ambiguous
        context.overflowBounds += await reader.overflowBounds(displayID: context.displayID)
        return !isLocked
    }

    /// Geometry and overflow evidence read after one source's pixels, so no source inherits positions read before
    /// its own screenshot. Overflow evidence only accumulates. Nil when the screen locked meanwhile.
    private func contextAfterSource() async -> CropContext? {
        var refreshed = context
        if context.validateFreshBounds {
            let items = await reader.menuBarItems(displayID: context.displayID)
            guard !isLocked else { return nil }
            refreshed.postCaptureBounds = Dictionary(
                items.map { ($0.uniqueIdentifier, $0.bounds) }, uniquingKeysWith: { first, _ in first }
            )
        }
        refreshed.overflowBounds += await reader.overflowBounds(displayID: context.displayID)
        guard !isLocked else { return nil }
        return refreshed
    }

    /// False for an item the hosting read couldn't identify, or that moved.
    private static func mayTryAnotherSource(
        _ candidate: (item: MenuBarItem, bounds: CGRect),
        context: CropContext
    ) -> Bool {
        guard context.hasHostingCapture else { return true }
        let identifier = candidate.item.uniqueIdentifier
        guard !context.ambiguousIdentifiers.contains(identifier), let bounds = context.postCaptureBounds[identifier]
        else { return false }
        return AXCropRules.hasStableCaptureBounds(before: candidate.bounds, after: bounds)
    }

    private mutating func cropSource(
        _ candidates: [(item: MenuBarItem, bounds: CGRect)],
        capture: ScreenCapture.MenuBarHostingCapture,
        source: AXCropRules.CaptureSource,
        context: CropContext
    ) {
        guard !isLocked else { return }
        let sourceLabel = switch source {
        case .hosting: "hosting window"
        case .barWindow: "bar window"
        case .displayStrip: "display strip"
        }
        Self.diagLog.debug(
            "axBoundsCapture: \(sourceLabel) \(capture.image.width)×\(capture.image.height)px, cropping \(candidates.count) item(s)"
        )
        let isStrip = source == .displayStrip
        let readLivePositions = isStrip || source == .hosting
        let rules = AXCropRules.SourceRules(
            knockOutBackground: isStrip,
            validateFreshBounds: readLivePositions || context.validateFreshBounds,
            absenceMeansMoved: readLivePositions || !context.validateFreshBounds,
            postCaptureBoundsByID: context.postCaptureBounds,
            captureTimeBoundsByID: context.captureTimeBounds,
            overflowBounds: context.overflowBounds,
            concealedIdentifiers: context.concealedIdentifiers,
            ambiguousIdentifiers: context.ambiguousIdentifiers,
            forgivenTags: context.forgivenTags
        )
        let reader = reader
        for (item, bounds) in candidates {
            let verdict = AXCropRules.verdict(
                for: AXCropRules.Candidate(item: item, bounds: bounds, capture: capture, source: source),
                rules: rules,
                claimedCropRects: claimedCropRects[source, default: [:]],
                displayBounds: { reader.displayBounds() },
                shouldSkip: shouldSkip
            )
            if case let .cropped(_, cropRect) = verdict {
                claimedCropRects[source, default: [:]][cropRect] = item.tag
            }
            pass.record(verdict, for: item)
        }
    }

    private static func isPlausibleCapture(_ capture: ScreenCapture.MenuBarHostingCapture) -> Bool {
        AXCropRules.isPlausibleHostingCapture(
            imageWidth: capture.image.width,
            imageHeight: capture.image.height,
            windowFrame: capture.windowFrame,
            scale: capture.scale
        )
    }
}
