//
//  RevealCaptureSession.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

/// Reveals hidden items one batch at a time and crops each batch from one screenshot pair.
/// It stops at the first batch that may not publish, and never publishes itself: commit does.
@MainActor
struct RevealCaptureSession {
    /// The live bar as a grouped reveal reads it, so a test can script the
    /// reveal's settle and its screenshot without a screen.
    struct Sources {
        /// The revealed members that reached stable bounds, paired with the
        /// request they answer. See waitForRevealedItems(matching:clock:read:).
        let settledItems: @MainActor ([MenuBarItem]) async -> [(requested: MenuBarItem, live: MenuBarItem)]
        /// The wait between stable AX bounds and fully rendered glyphs at those bounds.
        /// Says which of the items, by position, were still changing at the end of it.
        let renderSettle: @MainActor ([MenuBarItem]) async -> PixelSettle
        let reader: any MenuBarCaptureReading

        /// Asked right before each batch's reveal, since the hiding method can
        /// change while a pass is suspended between batches.
        var mayReveal: @MainActor () -> Bool = { true }
    }

    typealias RevealedPairs = [(requested: MenuBarItem, live: MenuBarItem)]

    let sources: Sources
    let displayID: CGDirectDisplayID
    let reveal: @MainActor (String) -> Void
    let conceal: @MainActor (String) -> Void
    /// Returns once no item move is running, since a reveal during a move reflows the bar under the drag.
    let waitWhileMoving: @MainActor () async -> Void
    /// Whether the screen is locked, logged under the step that asks; a lock ends the session.
    let isLocked: @MainActor (String) -> Bool
    let cropper: AXBoundsCropper
    let shouldSkip: @Sendable (MenuBarItem) -> Bool
    /// Admits a settled batch right before its screenshot. Nil ends the session without taking pixels.
    let admit: @MainActor () -> CapturePublicationAdmission?
    /// Publishes one cropped batch with nothing awaited since the screenshot. False ends the session.
    let commit: @MainActor (AXBoundsCropper.CapturePass, RevealedPairs, CapturePublicationAdmission) -> Bool

    /// - Returns: The items of the batches the session got through: published, or never drawn when revealed.
    ///   A batch it stopped at, or never reached, is left out.
    @discardableResult
    func capture(_ batches: [[MenuBarItem]]) async -> [MenuBarItem] {
        var reached = [MenuBarItem]()
        for batch in batches {
            await waitWhileMoving()
            guard !Task.isCancelled, !isLocked("revealing capture batch"), sources.mayReveal() else { return reached }

            for item in batch {
                reveal(item.uniqueIdentifier)
            }
            defer {
                for item in batch {
                    conceal(item.uniqueIdentifier)
                }
            }

            let firstRead = await sources.settledItems(batch)
            guard !isLocked("capture reveal completed") else { return reached }
            guard !firstRead.isEmpty else {
                reached += batch
                continue
            }

            // AX bounds stabilize before MenuBarAgent finishes drawing the revealed glyphs, so the batch settles once.
            let (revealed, pixelSettle) = await settleAtFinalFrames(firstRead)
            guard !Task.isCancelled, !isLocked("settled capture batch") else { return reached }

            // Admitted now, with nothing awaited before the screenshot. The reveal's own restriction rebuild moves the
            // layout generation, so an earlier admission would reject every batch.
            guard let admission = admit() else { return reached }

            // One hosting and one strip screenshot for the batch, on the fixed display, so every crop comes from one
            // instant of the bar. These were revealed here, so none is concealed and each is cut where it is drawn.
            let request = AXBoundsCropper.Request(
                items: revealed.map { ($0.live, $0.live.bounds) },
                displayID: displayID,
                validateFreshBounds: true,
                seatsOnDrawnBar: true
            )
            var captureResult = await cropper.crop(request, using: sources.reader, skipping: shouldSkip)
            let changing = Set(revealed.indices.filter { pixelSettle.mayBeChanging(at: $0) }.map { revealed[$0].live.tag })
            Self.dropCutOffPictures(from: &captureResult, amongChanging: changing)

            guard commit(captureResult, revealed, admission) else { return reached }
            reached += batch
        }
        return reached
    }

    /// Settles a revealed batch where it ends up. Native hiding rebuilds the bar, so an item can move after its
    /// first read; when one did, the batch settles again at the new frames.
    /// The second value says which of the pairs returned, by position, were still changing there.
    private func settleAtFinalFrames(_ firstRead: RevealedPairs) async -> (RevealedPairs, PixelSettle) {
        let settled = await sources.renderSettle(firstRead.map(\.live))
        guard !Task.isCancelled else { return (firstRead, settled) }
        // Only what appeared: an item that never drew would cost another full wait.
        let reread = await sources.settledItems(firstRead.map(\.requested))
        guard Self.anyRevealMoved(from: firstRead, to: reread) else { return (firstRead, settled) }
        MenuBarItemImageCache.diagLog.debug("grouped reveal capture: items moved after their first read; settling again where they ended up")
        return await (reread, sources.renderSettle(reread.map(\.live)))
    }

    /// Takes out the pictures, of the items whose pixels were still changing at the screenshot, whose ink runs
    /// into their left or right edge: such a picture is most likely the icon caught while it slides in. Either
    /// sign alone is not enough. An icon that keeps redrawing never settles, and one can draw to its edge.
    private static nonisolated func dropCutOffPictures(
        from pass: inout AXBoundsCropper.CapturePass,
        amongChanging changing: Set<MenuBarItemTag>
    ) {
        let cutOff = pass.captured.filter {
            changing.contains($0.key)
                && (MenuBarItemImageCache.isClippedAtLeadingEdge($0.value) || MenuBarItemImageCache.isClippedAtTrailingEdge($0.value))
        }.keys
        guard !cutOff.isEmpty else { return }
        for tag in cutOff {
            pass.captured[tag] = nil
        }
        pass.recoveredItems.removeAll { cutOff.contains($0.tag) }
        MenuBarItemImageCache.diagLog.debug(
            "grouped reveal capture: pixels were still changing and \(cutOff.count) picture(s) are cut off at an edge; not publishing \(cutOff.map(\.description).sorted())"
        )
    }

    /// Whether a second read put any item of the first somewhere else.
    private static nonisolated func anyRevealMoved(from first: RevealedPairs, to second: RevealedPairs) -> Bool {
        let earlier = Dictionary(first.map { ($0.requested.uniqueIdentifier, $0.live.bounds) }, uniquingKeysWith: { first, _ in first })
        return second.contains { pair in
            earlier[pair.requested.uniqueIdentifier].map { !AXCropRules.hasStableCaptureBounds(before: $0, after: pair.live.bounds) } ?? false
        }
    }
}
