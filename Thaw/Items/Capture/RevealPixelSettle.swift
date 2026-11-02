//
//  RevealPixelSettle.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import ThawCapture

extension MenuBarItemImageCache {
    /// The tags a capture the person asked for got a new picture of. Nil when no
    /// such capture is running, so automatic passes record nothing.
    static var requestedCaptureTally: Set<MenuBarItemTag>?

    /// Waits for a revealed batch to stop moving before its screenshot. See
    /// waitForSettledPixels(minimumSettle:interval:budget:sleep:read:).
    func settleRevealedPixels(_ revealed: [MenuBarItem], displayID: CGDirectDisplayID) async {
        let frames = revealed.map(\.bounds)
        let reader = LiveMenuBarCaptureReader()
        let settled = await Self.waitForSettledPixels {
            await reader.hostingCapture(displayID: displayID).map { Self.pixelFingerprint(of: frames, in: $0) }
        }
        if !settled {
            Self.diagLog.debug("grouped reveal capture: pixels still changing at the settle budget")
        }
    }

    /// Commits the ledger, first noting which revealed items this batch gives a
    /// new picture: a crop the cache will keep over the picture it has.
    func commitCaptureLedger(
        of captureResult: CapturePass,
        notingRevealed revealed: [(requested: MenuBarItem, live: MenuBarItem)]
    ) {
        if Self.requestedCaptureTally != nil {
            for pair in revealed {
                guard let image = captureResult.captured[pair.live.tag] else { continue }
                let kept = capturesByTag[pair.requested.tag].map { Self.preferredCachedImage(existing: $0, candidate: image) }
                if kept == nil || kept == image {
                    Self.requestedCaptureTally?.insert(pair.requested.tag)
                }
            }
        }
        commitCaptureLedger(of: captureResult)
    }

    /// Waits until two reads of the revealed items' pixels match.
    ///
    /// AX reports an item's final frame while MenuBarAgent is still sliding its
    /// glyph there, so a crop by that frame can cut the glyph off. Ends at the
    /// budget for an icon that keeps changing, or when the bar can't be read.
    ///
    /// - Returns: False when the budget ran out first.
    @MainActor
    @discardableResult
    static func waitForSettledPixels(
        minimumSettle: Duration = Constants.MenuBarTuning.layoutPrewarmRenderSettle,
        interval: Duration = .milliseconds(100),
        budget: Duration = Constants.MenuBarTuning.revealCapturePixelSettleBudget,
        sleep: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        read: @MainActor () async -> [Data]?
    ) async -> Bool {
        await sleep(minimumSettle)
        let deadline = ContinuousClock.now + budget
        guard var previous = await read() else { return true }
        while !Task.isCancelled, ContinuousClock.now < deadline {
            await sleep(interval)
            guard let current = await read() else { return true }
            if current == previous {
                return true
            }
            previous = current
        }
        return Task.isCancelled
    }

    /// The pixels each frame covers in a capture, for comparing two reads.
    static nonisolated func pixelFingerprint(
        of frames: [CGRect],
        in capture: ScreenCapture.MenuBarHostingCapture
    ) -> [Data] {
        frames.compactMap { frame in
            guard let mapping = capture.cropMapping(forItemBounds: frame),
                  let crop = capture.image.cropping(to: mapping.clamped),
                  let pixels = crop.detachedCopy().dataProvider?.data
            else { return nil }
            return pixels as Data
        }
    }
}
