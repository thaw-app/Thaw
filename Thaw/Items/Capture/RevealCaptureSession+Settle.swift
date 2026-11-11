//
//  RevealCaptureSession+Settle.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import ThawCapture

extension RevealCaptureSession {
    /// The time the settle waits read and sleep on, so a test can run them without real time passing.
    struct SettleClock {
        var now: @MainActor () -> ContinuousClock.Instant = { .now }
        var sleep: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    }

    /// Polls a revealed batch, one enumeration per poll, until every member's AX bounds are stable.
    /// - Returns: The settled members paired with their requests, in request order; one that never settled is left out.
    static func waitForRevealedItems(
        matching items: [MenuBarItem],
        clock: SettleClock = SettleClock(),
        read: @MainActor () async -> [MenuBarItem]
    ) async -> RevealedPairs {
        guard !items.isEmpty else { return [] }

        // MenuBarAgent can take over a second to publish a revealed item.
        // The loop leaves as soon as every member settles.
        let maxAttempts = 20
        var previousByIdentifier = [String: MenuBarItem]()
        var settledByIdentifier = [String: MenuBarItem]()
        let deadline = clock.now() + Constants.MenuBarTuning.revealCaptureSettleBudget

        for attempt in 0 ..< maxAttempts {
            guard !Task.isCancelled, clock.now() < deadline else { break }

            let liveItems = await read()

            // Settled members stay in the match so their claim can't go to a second request.
            let matches = MenuBarItemImageCache.revealMatches(requests: items, live: liveItems)
            let currentByIdentifier = Dictionary(
                matches.enumerated().compactMap { index, liveItem in
                    liveItem.map { (items[index].uniqueIdentifier, $0) }
                },
                uniquingKeysWith: { first, _ in first }
            )

            let advanced = MenuBarItemImageCache.advanceRevealSettle(
                settled: settledByIdentifier,
                previous: previousByIdentifier,
                current: currentByIdentifier,
                hasStable: { AXCropRules.hasStableCaptureBounds(before: $0, after: $1) }
            )
            settledByIdentifier = advanced.settled
            previousByIdentifier = advanced.previous

            if settledByIdentifier.count == items.count {
                break
            }
            if attempt < maxAttempts - 1 {
                await clock.sleep(.milliseconds(100))
            }
        }

        if settledByIdentifier.count < items.count {
            let missing = items
                .filter { settledByIdentifier[$0.uniqueIdentifier] == nil }
                .map(\.logString)
            let budgetEnding = clock.now() < deadline ? "in \(maxAttempts) polls" : "within the settle budget"
            let ending = Task.isCancelled ? "before the wait was cancelled" : budgetEnding
            MenuBarItemImageCache.diagLog.debug(
                "waitForRevealedItems: \(missing.count) of \(items.count) revealed item(s) never settled \(ending); no capture for \(missing)"
            )
        }
        return items.compactMap { item in
            settledByIdentifier[item.uniqueIdentifier].map { (requested: item, live: $0) }
        }
    }

    /// Waits for a revealed batch to stop moving before its screenshot. See
    /// waitForSettledPixels(minimumSettle:interval:requiredMatches:budget:clock:read:).
    static func settleRevealedPixels(
        _ revealed: [MenuBarItem],
        displayID: CGDirectDisplayID,
        reader: any MenuBarCaptureReading,
        clock: SettleClock = SettleClock()
    ) async {
        let frames = revealed.map(\.bounds)
        let settled = await waitForSettledPixels(clock: clock) {
            await reader.hostingCapture(displayID: displayID).map { pixelFingerprint(of: frames, in: $0) }
        }
        if !settled {
            MenuBarItemImageCache.diagLog.debug("grouped reveal capture: pixels still changing at the settle budget")
        }
    }

    /// Waits for three matching pixel reads in a row, since AX reports the final frame while the glyph still slides.
    /// - Returns: False when the budget ran out first.
    @discardableResult
    static func waitForSettledPixels(
        minimumSettle: Duration = Constants.MenuBarTuning.layoutPrewarmRenderSettle,
        interval: Duration = .milliseconds(100),
        requiredMatches: Int = 2,
        budget: Duration = Constants.MenuBarTuning.revealCapturePixelSettleBudget,
        clock: SettleClock = SettleClock(),
        read: @escaping @MainActor () async -> [Data]?
    ) async -> Bool {
        await clock.sleep(minimumSettle)
        let deadline = clock.now() + budget
        guard case let .read(first) = await readBefore(deadline, clock: clock, read) else { return false }
        guard var previous = first else { return true }
        var matches = 0
        while !Task.isCancelled, clock.now() < deadline {
            await clock.sleep(interval)
            guard case let .read(next) = await readBefore(deadline, clock: clock, read) else { return false }
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
    /// The timer that ends a read still runs on real time.
    static func readBefore(
        _ deadline: ContinuousClock.Instant,
        clock: SettleClock,
        _ read: @escaping @MainActor () async -> [Data]?
    ) async -> BoundedRead {
        guard clock.now() < deadline else { return .pastDeadline }
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
        if case .read = outcome, clock.now() >= deadline {
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
