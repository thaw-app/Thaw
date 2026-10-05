//
//  MenuBarItemImageCache+AXCapture.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import ThawCapture

extension MenuBarItemImageCache {
    private nonisolated struct AXCropContext {
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
        var hasStripGeometry = false
    }

    @concurrent
    nonisolated func axBoundsCapture(
        _ itemsWithBounds: [(item: MenuBarItem, bounds: CGRect)],
        scale _: CGFloat,
        displayID: CGDirectDisplayID,
        validateFreshBounds: Bool,
        concealedIdentifiers: Set<String>,
        forgivenTags: Set<MenuBarItemTag> = [],
        using reader: any MenuBarCaptureReading = LiveMenuBarCaptureReader()
    ) async -> CapturePass {
        guard !screenIsLocked(), !itemsWithBounds.isEmpty else { return CapturePass() }
        let band = await reader.captureBand(displayID: displayID)
        guard !screenIsLocked() else { return CapturePass() }
        let overflowBounds = await reader.overflowBounds(displayID: displayID)
        guard !screenIsLocked() else { return CapturePass() }
        var result = CapturePass()
        // Staged, not applied: the ledger is read-only until the pass commits.
        result.forgivenTags = forgivenTags
        let candidates = eligibleAXCaptureCandidates(
            itemsWithBounds, band: band, overflowBounds: overflowBounds, into: &result
        )
        guard !candidates.isEmpty else {
            Self.diagLog.debug("axBoundsCapture: no trustworthy status-item bounds; skipping screenshot")
            return result
        }
        var context = AXCropContext(
            displayID: displayID,
            validateFreshBounds: validateFreshBounds,
            concealedIdentifiers: concealedIdentifiers,
            forgivenTags: forgivenTags,
            captureTimeBounds: Dictionary(
                candidates.map { ($0.item.uniqueIdentifier, $0.bounds) },
                uniquingKeysWith: { first, _ in first }
            ),
            overflowBounds: overflowBounds
        )
        await captureAXStrip(candidates, context: &context, using: reader, into: &result)
        guard !screenIsLocked() else { return CapturePass() }
        let unresolved = candidates.filter { candidate in
            guard !result.captured.keys.contains(candidate.item.tag) else { return false }
            // A different pixel source cannot repair an unidentified or moved item.
            guard context.hasStripGeometry else { return true }
            let identifier = candidate.item.uniqueIdentifier
            guard !context.ambiguousIdentifiers.contains(identifier),
                  let bounds = context.postCaptureBounds[identifier]
            else { return false }
            return Self.hasStableCaptureBounds(before: candidate.bounds, after: bounds)
        }
        if !unresolved.isEmpty {
            await captureAXWindowSources(unresolved, context: &context, using: reader, into: &result)
        }
        return screenIsLocked() ? CapturePass() : result
    }

    private nonisolated func eligibleAXCaptureCandidates(
        _ candidates: [(item: MenuBarItem, bounds: CGRect)],
        band: (frame: CGRect, menuMaxX: CGFloat?),
        overflowBounds: [CGRect],
        into result: inout CapturePass
    ) -> [(item: MenuBarItem, bounds: CGRect)] {
        let peers = candidates.map(\.item)
        return candidates.filter { item, bounds in
            // Parked/overlapping frames cannot identify this item's pixels.
            // Skip without invalidating the glyph captured while it was seated.
            if Self.hasUnusableCaptureGeometry(item, among: peers) {
                Self.diagLog.debug("axBoundsCapture: \(item.logString) frame is parked or phantom; keeping its prior capture")
                return false
            }
            let overlapsOverflow = Self.isContaminatedByNativeOverflow(bounds, overflowBounds: overflowBounds)
            let plausible = Self.isPlausibleItemCaptureBounds(bounds)
                && Self.isInStatusItemCaptureBand(bounds: bounds, applicationMenuMaxX: band.menuMaxX)
                && !overlapsOverflow
            if !plausible {
                if overlapsOverflow {
                    Self.diagLog.debug("axBoundsCapture: rejecting native-overflow-contaminated bounds for \(item.logString)")
                }
                result.unreadable.append(item)
                result.invalidatedTags.insert(item.tag)
            }
            return plausible
        }
    }

    private nonisolated func captureAXWindowSources(
        _ candidates: [(item: MenuBarItem, bounds: CGRect)],
        context: inout AXCropContext,
        using reader: any MenuBarCaptureReading,
        into result: inout CapturePass
    ) async {
        let hosting = await readAXHostingCapture(candidates, displayID: context.displayID, using: reader, into: &result)
        guard !screenIsLocked() else { return }
        var hostingOwners = [CGRect: MenuBarItemTag]()
        if let hosting {
            guard let sourceContext = await contextAfterSource(context, using: reader) else { return }
            context.overflowBounds = sourceContext.overflowBounds
            appendAXSourceCrops(
                candidates,
                capture: hosting,
                source: .hosting,
                context: sourceContext,
                cropRectOwners: &hostingOwners,
                into: &result
            )
        }
        // Some apps draw in an owner window rather than MenuBarAgent's window.
        // A missing hosting capture must still reach this stage.
        let unresolved = candidates.filter { !result.captured.keys.contains($0.item.tag) }
        var windowOwners = [CGRect: MenuBarItemTag]()
        for ownerPID in Set(unresolved.map(\.item.ownerPID)).sorted() {
            guard !screenIsLocked() else { return }
            let capture = await reader.barWindowCapture(ownerPID: ownerPID, displayID: context.displayID)
            guard !screenIsLocked() else { return }
            guard let capture else { continue }
            // Each owner window is its own acquisition interval: the hosting
            // read cannot vouch for pixels taken after it.
            guard let sourceContext = await contextAfterSource(context, using: reader) else { return }
            context.overflowBounds = sourceContext.overflowBounds
            appendAXSourceCrops(
                unresolved.filter { $0.item.ownerPID == ownerPID },
                capture: capture,
                source: .barWindow,
                context: sourceContext,
                cropRectOwners: &windowOwners,
                into: &result
            )
        }
    }

    /// Geometry and overflow evidence read after one source's pixels arrived.
    ///
    /// The returned context belongs to that source alone, so a later source
    /// never inherits positions read before its own screenshot. Overflow
    /// evidence only accumulates, since a control that appeared during any
    /// source can contaminate the crops. Nil when the screen locked meanwhile.
    private nonisolated func contextAfterSource(
        _ context: AXCropContext,
        using reader: any MenuBarCaptureReading
    ) async -> AXCropContext? {
        var refreshed = context
        if context.validateFreshBounds {
            let items = await reader.menuBarItems(displayID: context.displayID)
            guard !screenIsLocked() else { return nil }
            refreshed.postCaptureBounds = Dictionary(
                items.map { ($0.uniqueIdentifier, $0.bounds) }, uniquingKeysWith: { first, _ in first }
            )
        }
        refreshed.overflowBounds += await reader.overflowBounds(displayID: context.displayID)
        guard !screenIsLocked() else { return nil }
        return refreshed
    }

    private nonisolated func readAXHostingCapture(
        _ candidates: [(item: MenuBarItem, bounds: CGRect)],
        displayID: CGDirectDisplayID,
        using reader: any MenuBarCaptureReading,
        into result: inout CapturePass
    ) async -> ScreenCapture.MenuBarHostingCapture? {
        guard !screenIsLocked() else { return nil }
        let capture = await reader.hostingCapture(displayID: displayID)
        guard !screenIsLocked() else { return nil }
        if let capture, Self.isPlausibleAXCapture(capture) {
            hostingFailureWarnedDisplays.withLock { _ = $0.remove(displayID) }
            return capture
        }
        let firstFailure = hostingFailureWarnedDisplays.withLock { $0.insert(displayID).inserted }
        let message = "axBoundsCapture: captureMenuBarHostingWindowAsync failed for \(candidates.count) items"
        if firstFailure {
            Self.diagLog.warning(message)
        } else {
            Self.diagLog.debug(message)
        }
        result.unreadable.append(contentsOf: candidates.map(\.item))
        result.invalidatedTags.formUnion(candidates.map(\.item.tag))
        return nil
    }

    private nonisolated func captureAXStrip(
        _ candidates: [(item: MenuBarItem, bounds: CGRect)],
        context: inout AXCropContext,
        using reader: any MenuBarCaptureReading,
        into result: inout CapturePass
    ) async {
        guard !screenIsLocked(), !candidates.isEmpty else { return }
        let capture = await reader.displayStripCapture(displayID: context.displayID)
        guard !screenIsLocked() else { return }
        guard let capture, Self.isPlausibleAXCapture(capture) else {
            Self.diagLog.warning("axBoundsCapture: captureMenuBarDisplayStripAsync failed for \(candidates.count) items")
            result.unreadable.append(contentsOf: candidates.map(\.item))
            result.invalidatedTags.formUnion(candidates.map(\.item.tag))
            return
        }
        // A hosting enumeration cannot establish ownership of on-screen pixels.
        let live = await reader.liveBounds(for: candidates)
        guard !screenIsLocked() else { return }
        context.hasStripGeometry = true
        context.postCaptureBounds = live.bounds
        context.ambiguousIdentifiers = live.ambiguous
        context.overflowBounds += await reader.overflowBounds(displayID: context.displayID)
        guard !screenIsLocked() else { return }
        var stripOwners = [CGRect: MenuBarItemTag]()
        appendAXSourceCrops(
            candidates,
            capture: capture,
            source: .displayStrip,
            context: context,
            cropRectOwners: &stripOwners,
            into: &result
        )
    }

    private nonisolated func appendAXSourceCrops(
        _ candidates: [(item: MenuBarItem, bounds: CGRect)],
        capture: ScreenCapture.MenuBarHostingCapture,
        source: CaptureSource,
        context: AXCropContext,
        cropRectOwners: inout [CGRect: MenuBarItemTag],
        into result: inout CapturePass
    ) {
        guard !screenIsLocked() else { return }
        let sourceLabel = switch source {
        case .hosting: "hosting window"
        case .barWindow: "bar window"
        case .displayStrip: "display strip"
        }
        Self.diagLog.debug(
            "axBoundsCapture: \(sourceLabel) \(capture.image.width)×\(capture.image.height)px, cropping \(candidates.count) item(s)"
        )
        let isStrip = source == .displayStrip
        appendAXBoundsCrops(
            from: candidates,
            capture: capture,
            source: source,
            knockOutBackground: isStrip,
            validateFreshBounds: isStrip || context.validateFreshBounds,
            absenceMeansMoved: isStrip || !context.validateFreshBounds,
            postCaptureBoundsByID: context.postCaptureBounds,
            captureTimeBoundsByID: context.captureTimeBounds,
            overflowBounds: context.overflowBounds,
            concealedIdentifiers: context.concealedIdentifiers,
            ambiguousIdentifiers: context.ambiguousIdentifiers,
            forgivenTags: context.forgivenTags,
            cropRectOwners: &cropRectOwners,
            into: &result
        )
    }

    private static nonisolated func isPlausibleAXCapture(_ capture: ScreenCapture.MenuBarHostingCapture) -> Bool {
        isPlausibleHostingCapture(
            imageWidth: capture.image.width,
            imageHeight: capture.image.height,
            windowFrame: capture.windowFrame,
            scale: capture.scale
        )
    }
}
