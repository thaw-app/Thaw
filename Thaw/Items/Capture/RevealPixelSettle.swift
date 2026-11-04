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
    /// The tags one requested capture got a new picture of. Each request owns one.
    @MainActor
    final class RequestedCaptureTally {
        var tags: Set<MenuBarItemTag> = []
    }

    /// The tally of the pass holding the prewarm slot. Nil for an automatic pass,
    /// so it records nothing. Set and cleared only by the slot.
    static var requestedCaptureTally: RequestedCaptureTally?

    /// Waits for a revealed batch to stop moving before its screenshot. See
    /// waitForSettledPixels(minimumSettle:interval:requiredMatches:budget:sleep:read:).
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

    /// Commits the ledger after noting which revealed items got a new picture: a
    /// crop the cache keeps over the one it has.
    func commitCaptureLedger(
        of captureResult: CapturePass,
        notingRevealed revealed: [(requested: MenuBarItem, live: MenuBarItem)]
    ) {
        if let tally = Self.requestedCaptureTally {
            for pair in revealed {
                guard let image = captureResult.captured[pair.live.tag] else { continue }
                let kept = capturesByTag[pair.requested.tag].map { Self.preferredCachedImage(existing: $0, candidate: image) }
                if kept == nil || kept == image {
                    tally.tags.insert(pair.requested.tag)
                }
            }
        }
        commitCaptureLedger(of: captureResult)
    }

    /// Waits until three reads in a row of the revealed items' pixels match.
    ///
    /// AX reports an item's final frame while MenuBarAgent is still sliding its
    /// glyph there, so a crop by that frame can cut the glyph off. A bar that moves in steps
    /// can repeat one frame mid-slide, so a single matching pair isn't enough. Ends at the
    /// budget for an icon that keeps changing, or when the bar can't be read.
    /// Each read gets only the time left, so a slow screenshot can't hold the reveal.
    ///
    /// - Returns: False when the budget ran out first.
    @MainActor
    @discardableResult
    static func waitForSettledPixels(
        minimumSettle: Duration = Constants.MenuBarTuning.layoutPrewarmRenderSettle,
        interval: Duration = .milliseconds(100),
        requiredMatches: Int = 2,
        budget: Duration = Constants.MenuBarTuning.revealCapturePixelSettleBudget,
        sleep: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        read: @escaping @MainActor () async -> [Data]?
    ) async -> Bool {
        await sleep(minimumSettle)
        let deadline = ContinuousClock.now + budget
        guard case let .read(first) = await readBefore(deadline, read) else { return false }
        guard var previous = first else { return true }
        var matches = 0
        while !Task.isCancelled, ContinuousClock.now < deadline {
            await sleep(interval)
            guard case let .read(next) = await readBefore(deadline, read) else { return false }
            guard let current = next else { return true }
            matches = current == previous ? matches + 1 : 0
            if matches >= requiredMatches {
                return true
            }
            previous = current
        }
        return Task.isCancelled
    }

    nonisolated enum BoundedRead: Sendable {
        case read([Data]?)
        case pastDeadline
    }

    /// Runs read against the deadline. A result that arrives at or after it doesn't count.
    @MainActor
    static func readBefore(_ deadline: ContinuousClock.Instant, _ read: @escaping @MainActor () async -> [Data]?) async -> BoundedRead {
        guard ContinuousClock.now < deadline else { return .pastDeadline }
        let (outcomes, sink) = AsyncStream.makeStream(of: BoundedRead.self)
        let timer = Task {
            try? await Task.sleep(until: deadline)
            sink.yield(.pastDeadline)
        }
        Task { @MainActor in await sink.yield(.read(read())) }
        var outcome = BoundedRead.pastDeadline
        for await first in outcomes {
            outcome = first
            break
        }
        timer.cancel()
        sink.finish()
        if case .read = outcome, ContinuousClock.now >= deadline {
            return .pastDeadline
        }
        return outcome
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
