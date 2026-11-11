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
        let renderSettle: @MainActor ([MenuBarItem]) async -> Void
        let reader: any MenuBarCaptureReading
        /// Raised before a batch is revealed and lowered after it is concealed,
        /// so the user sees the bar as it was while the capture sees the reveal.
        var cover: @MainActor () -> Void = {
            // No cover unless the caller supplies one, as in tests.
        }

        var uncover: @MainActor () -> Void = {
            // Nothing to take down when no cover was raised.
        }

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

    func capture(_ batches: [[MenuBarItem]]) async {
        for batch in batches {
            await waitWhileMoving()
            guard !Task.isCancelled, !isLocked("revealing capture batch"), sources.mayReveal() else { return }

            sources.cover()
            for item in batch {
                reveal(item.uniqueIdentifier)
            }
            defer {
                for item in batch {
                    conceal(item.uniqueIdentifier)
                }
                sources.uncover()
            }

            let firstRead = await sources.settledItems(batch)
            guard !isLocked("capture reveal completed") else { return }
            guard !firstRead.isEmpty else { continue }

            // AX bounds stabilize before MenuBarAgent finishes drawing the revealed glyphs, so the batch settles once.
            let revealed = await settleAtFinalFrames(firstRead)
            guard !Task.isCancelled, !isLocked("settled capture batch") else { return }

            // Admitted now, with nothing awaited before the screenshot. The reveal's own restriction rebuild moves the
            // layout generation, so an earlier admission would reject every batch.
            guard let admission = admit() else { return }

            // One hosting and one strip screenshot for the batch, on the fixed display, so every crop comes from one
            // instant of the bar. These items were revealed here, so none is concealed.
            let request = AXBoundsCropper.Request(
                items: revealed.map { ($0.live, $0.live.bounds) },
                displayID: displayID,
                validateFreshBounds: true
            )
            let captureResult = await cropper.crop(request, using: sources.reader, skipping: shouldSkip)

            guard commit(captureResult, revealed, admission) else { return }
        }
    }

    /// Settles a revealed batch where it ends up. Native hiding rebuilds the bar, so an item can move after its
    /// first read; when one did, the batch settles again at the new frames.
    private func settleAtFinalFrames(_ firstRead: RevealedPairs) async -> RevealedPairs {
        await sources.renderSettle(firstRead.map(\.live))
        guard !Task.isCancelled else { return firstRead }
        // Only what appeared: an item that never drew would cost another full wait.
        let reread = await sources.settledItems(firstRead.map(\.requested))
        guard Self.anyRevealMoved(from: firstRead, to: reread) else { return firstRead }
        MenuBarItemImageCache.diagLog.debug("grouped reveal capture: items moved after their first read; settling again where they ended up")
        await sources.renderSettle(reread.map(\.live))
        return reread
    }

    /// Whether a second read put any item of the first somewhere else.
    private static nonisolated func anyRevealMoved(from first: RevealedPairs, to second: RevealedPairs) -> Bool {
        let earlier = Dictionary(first.map { ($0.requested.uniqueIdentifier, $0.live.bounds) }, uniquingKeysWith: { first, _ in first })
        return second.contains { pair in
            earlier[pair.requested.uniqueIdentifier].map { !AXCropRules.hasStableCaptureBounds(before: $0, after: pair.live.bounds) } ?? false
        }
    }
}
