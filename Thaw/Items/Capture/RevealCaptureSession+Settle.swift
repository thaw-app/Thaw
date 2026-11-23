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
        /// The timer that ends a read at the deadline; it must return early when cancelled.
        var sleepUntil: @MainActor (ContinuousClock.Instant) async -> Void = { try? await Task.sleep(until: $0) }
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

    /// Which frames of a settle wait were still changing when it ended.
    nonisolated enum PixelSettle: Equatable, Sendable {
        /// Every frame held still.
        case settled
        /// The frames at these positions were still changing at the budget.
        case changing(IndexSet)
        /// The bar couldn't be read, so nothing shows that any frame held still.
        case unread

        func mayBeChanging(at index: Int) -> Bool {
            switch self {
            case .settled: false
            case let .changing(indices): indices.contains(index)
            case .unread: true
            }
        }
    }

    /// Waits for a revealed batch to stop moving before its screenshot. See
    /// waitForSettledPixels(minimumSettle:interval:requiredMatches:budget:clock:read:).
    /// - Returns: The members, by position in revealed, whose pixels may still have been changing.
    @discardableResult
    static func settleRevealedPixels(
        _ revealed: [MenuBarItem],
        displayID: CGDirectDisplayID,
        reader: any MenuBarCaptureReading,
        clock: SettleClock = SettleClock()
    ) async -> PixelSettle {
        let frames = revealed.map(\.bounds)
        let settle = await waitForSettledPixels(clock: clock) {
            await reader.hostingCapture(displayID: displayID).map { pixelFingerprint(of: frames, in: $0) }
        }
        switch settle {
        case .settled: break
        case let .changing(indices):
            MenuBarItemImageCache.diagLog.debug(
                "grouped reveal capture: pixels still changing at the settle budget for \(indices.map { revealed[$0].logString })"
            )
        case .unread:
            MenuBarItemImageCache.diagLog.debug("grouped reveal capture: bar unreadable while settling; treating every item as still changing")
        }
        return settle
    }

    /// Waits for three matching reads of each frame, since AX reports the final frame while the glyph still slides.
    /// Frames are judged separately, so one icon that keeps redrawing doesn't mark its neighbours.
    static func waitForSettledPixels(
        minimumSettle: Duration = Constants.MenuBarTuning.layoutPrewarmRenderSettle,
        interval: Duration = .milliseconds(100),
        requiredMatches: Int = 2,
        budget: Duration = Constants.MenuBarTuning.revealCapturePixelSettleBudget,
        clock: SettleClock = SettleClock(),
        read: @escaping @MainActor () async -> [Data?]?
    ) async -> PixelSettle {
        await clock.sleep(minimumSettle)
        let deadline = clock.now() + budget
        guard case let .read(first) = await readBefore(deadline, clock: clock, read), var previous = first else { return .unread }
        var matches = [Int](repeating: 0, count: previous.count)
        while !Task.isCancelled, clock.now() < deadline {
            await clock.sleep(interval)
            guard case let .read(next) = await readBefore(deadline, clock: clock, read) else { break }
            guard let current = next, current.count == previous.count else { return .unread }
            for index in matches.indices {
                matches[index] = current[index] == previous[index] ? matches[index] + 1 : 0
            }
            if matches.allSatisfy({ $0 >= requiredMatches }) {
                return .settled
            }
            previous = current
        }
        // The caller checks for cancellation.
        guard !Task.isCancelled else { return .settled }
        return .changing(IndexSet(matches.indices.filter { matches[$0] < requiredMatches }))
    }

    nonisolated enum BoundedRead: Sendable {
        case read([Data?]?)
        case pastDeadline
    }

    /// Runs read against the deadline. A result that arrives at or after it doesn't count.
    static func readBefore(
        _ deadline: ContinuousClock.Instant,
        clock: SettleClock,
        _ read: @escaping @MainActor () async -> [Data?]?
    ) async -> BoundedRead {
        guard clock.now() < deadline else { return .pastDeadline }
        let (outcomes, sink) = AsyncStream.makeStream(of: BoundedRead.self)
        let timer = Task {
            await clock.sleepUntil(deadline)
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

    /// The pixels each frame covers in a capture, for comparing two reads; nil for a frame that can't be cut.
    static nonisolated func pixelFingerprint(
        of frames: [CGRect],
        in capture: ScreenCapture.MenuBarHostingCapture
    ) -> [Data?] {
        frames.map { frame in
            guard let mapping = capture.cropMapping(forItemBounds: frame),
                  let crop = capture.image.cropping(to: mapping.clamped),
                  let pixels = crop.detachedCopy().dataProvider?.data
            else { return nil }
            return pixels as Data
        }
    }
}
