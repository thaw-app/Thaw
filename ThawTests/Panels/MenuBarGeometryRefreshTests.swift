//
//  MenuBarGeometryRefreshTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import CoreGraphics
import Testing
@testable import Thaw

@MainActor
@Suite("Menu bar geometry refresh", .timeLimit(.minutes(1)))
struct MenuBarGeometryRefreshTests {
    @Test("Reveal reads geometry immediately instead of leaving icons outside the old pill")
    func revealReadsWithoutWaitingForSettle() async throws {
        let harness = GeometryRefreshHarness()
        defer { harness.close() }
        var sleeps = harness.clock.requests.makeAsyncIterator()
        var publications = harness.publications.makeAsyncIterator()

        harness.refresh.schedule(.visibilityChanged(isRevealed: true))
        try #require(await sleeps.next() == .zero)
        _ = try #require(await publications.next())
        #expect(harness.readCount == 1)
        #expect(!harness.isPending)
    }

    @Test("A fresh but pre-reflow answer is followed without waiting for discovery")
    func revealFollowsNativeReflowForABoundedInterval() async throws {
        let harness = GeometryRefreshHarness()
        defer { harness.close() }
        var publications = harness.publications.makeAsyncIterator()

        harness.refresh.schedule(.visibilityChanged(isRevealed: true))
        _ = try #require(await publications.next())
        try #require(harness.clock.nextWake == harness.clock.now + .milliseconds(100))

        let expanded = [CGRect(x: 50, y: 0, width: 74, height: 30)]
        harness.value.itemBounds = expanded
        harness.clock.advance(by: .milliseconds(100))
        #expect(await publications.next()?.itemBounds == expanded)
        #expect(!harness.isPending, "Follow-up reads must not freeze the old pill")

        harness.clock.advance(by: .milliseconds(250))
        _ = try #require(await publications.next())
        #expect(harness.clock.nextWake == nil, "Reveal must not start an indefinite polling loop")
        #expect(harness.readCount == 3)
    }

    @Test("Concealing cancels reveal follow-ups and keeps its own settle deadline")
    func concealCancelsRevealFollowUps() async throws {
        let harness = GeometryRefreshHarness()
        defer { harness.close() }
        var publications = harness.publications.makeAsyncIterator()
        harness.refresh.schedule(.visibilityChanged(isRevealed: true))
        _ = try #require(await publications.next())

        harness.refresh.schedule(.visibilityChanged(isRevealed: false))
        harness.clock.advance(by: .milliseconds(100))
        #expect(harness.readCount == 1)
        #expect(harness.isPending)
        harness.clock.advance(by: .milliseconds(250))
        _ = try #require(await publications.next())
        #expect(harness.readCount == 2)
        #expect(harness.clock.nextWake == nil)
        #expect(!harness.isPending)
    }

    @Test("Settled frame events do not postpone an in-flight reveal read")
    func settledFramesKeepRevealDeadline() async throws {
        let harness = GeometryRefreshHarness()
        defer { harness.close() }
        let gate = GeometryReadGate()
        defer { gate.resume(nil) }
        var entered = gate.started.makeAsyncIterator()
        var sleeps = harness.clock.requests.makeAsyncIterator()
        var publications = harness.publications.makeAsyncIterator()
        harness.readOperation = {
            harness.readCount == 1 ? await gate.read() : harness.value
        }

        harness.refresh.schedule(.visibilityChanged(isRevealed: true))
        _ = try #require(await entered.next())
        _ = try #require(await sleeps.next())
        harness.clock.advance(by: .milliseconds(20))
        harness.refresh.schedule(.geometryChanged)
        try #require(await sleeps.next() == .zero)
        let snapshot = try #require(await publications.next())
        #expect(snapshot.itemBounds == harness.value.itemBounds)
        #expect(harness.readCount == 2)
        #expect(harness.publishedSnapshots.count == 1)
        #expect(!harness.isPending)
    }

    @Test("Pre-toggle cached bounds cannot restore the cut-off pill, even after later frame events")
    func visibilityChangeRejectsOlderSnapshots() async throws {
        let harness = GeometryRefreshHarness()
        defer { harness.close() }
        let beforeToggle = harness.clock.now
        let stale = MenuBarGeometryRefresh.Snapshot(
            itemBounds: [CGRect(x: 200, y: 0, width: 100, height: 30)],
            chevronFrame: .zero,
            readAt: beforeToggle
        )
        harness.readOperation = { stale }
        var completions = harness.completions.makeAsyncIterator()
        harness.clock.advance(by: .milliseconds(10))
        let toggledAt = harness.clock.now

        harness.refresh.schedule(.visibilityChanged(isRevealed: true))
        _ = try #require(await completions.next())
        #expect(harness.publishedSnapshots.isEmpty)
        #expect(harness.readRequirements == [toggledAt])

        harness.refresh.schedule(.geometryChanged)
        harness.clock.advance(by: .milliseconds(200))
        _ = try #require(await completions.next())
        #expect(harness.publishedSnapshots.isEmpty)
        #expect(harness.readRequirements == [toggledAt, toggledAt])
    }

    @Test("Time queued on the main actor counts toward the settle deadline")
    func queuedWorkDoesNotAddAnotherDelay() async throws {
        let harness = GeometryRefreshHarness()
        defer { harness.close() }
        var sleeps = harness.clock.requests.makeAsyncIterator()
        var publications = harness.publications.makeAsyncIterator()

        harness.refresh.schedule(.geometryChanged)
        harness.clock.advance(by: .milliseconds(80))
        try #require(await sleeps.next() == .milliseconds(120))
        harness.clock.advance(by: .milliseconds(120))
        _ = try #require(await publications.next())
        #expect(harness.readCount == 1)
    }

    @Test("Geometry updates preserve the longer conceal settle")
    func geometryDoesNotShortenConcealSettle() async throws {
        let harness = GeometryRefreshHarness()
        defer { harness.close() }
        var sleeps = harness.clock.requests.makeAsyncIterator()
        var publications = harness.publications.makeAsyncIterator()

        harness.refresh.schedule(.visibilityChanged(isRevealed: false))
        #expect(await sleeps.next() == .milliseconds(350))
        harness.clock.advance(by: .milliseconds(100))
        harness.refresh.schedule(.geometryChanged)
        #expect(await sleeps.next() == .milliseconds(250))
        harness.clock.advance(by: .milliseconds(200))
        #expect(harness.readCount == 0)
        #expect(harness.isPending)

        harness.clock.advance(by: .milliseconds(50))
        _ = try #require(await publications.next())
        #expect(harness.readCount == 1)
        #expect(!harness.isPending)
    }

    @Test("A new visibility transition starts its own settle window")
    func visibilityChangeReplacesPriorDeadline() async throws {
        let harness = GeometryRefreshHarness()
        defer { harness.close() }
        var sleeps = harness.clock.requests.makeAsyncIterator()
        var publications = harness.publications.makeAsyncIterator()

        harness.refresh.schedule(.geometryChanged)
        _ = try #require(await sleeps.next())
        harness.clock.advance(by: .milliseconds(150))
        harness.refresh.schedule(.visibilityChanged(isRevealed: false))
        #expect(await sleeps.next() == .milliseconds(350))
        harness.clock.advance(by: .milliseconds(50))
        harness.refresh.schedule(.geometryChanged)
        #expect(await sleeps.next() == .milliseconds(300))
        #expect(harness.isPending)
        #expect(harness.readCount == 0)

        harness.clock.advance(by: .milliseconds(300))
        _ = try #require(await publications.next())
        #expect(harness.readCount == 1)
    }

    @Test("A superseded AX answer cannot replace fresh geometry or finish its pending read")
    func staleReadDoesNotPublishOrUnfreezeReplacement() async throws {
        let harness = GeometryRefreshHarness()
        defer { harness.close() }
        let gate = GeometryReadGate()
        defer { gate.resume(nil) }
        var entered = gate.started.makeAsyncIterator()
        var sleeps = harness.clock.requests.makeAsyncIterator()
        var publications = harness.publications.makeAsyncIterator()
        harness.readOperation = {
            if harness.readCount == 1 {
                return await gate.read()
            }
            return harness.value
        }

        harness.refresh.schedule(.immediate)
        _ = try #require(await entered.next())
        _ = try #require(await sleeps.next())
        harness.refresh.schedule(.visibilityChanged(isRevealed: false))
        _ = try #require(await sleeps.next())
        gate.resume(MenuBarGeometryRefresh.Snapshot(itemBounds: [], chevronFrame: .zero))
        harness.clock.advance(by: .milliseconds(350))
        _ = try #require(await publications.next())

        #expect(harness.readCount == 2)
        #expect(harness.publishedSnapshots.count == 1)
        #expect(harness.pendingChanges == [true, true, false])
    }

    @Test("Cancel abandons pending reads; the next request gets a new deadline")
    func cancellationResetsDeadline() async throws {
        let harness = GeometryRefreshHarness()
        defer { harness.close() }
        var sleeps = harness.clock.requests.makeAsyncIterator()
        var publications = harness.publications.makeAsyncIterator()

        harness.refresh.schedule(.geometryChanged)
        _ = try #require(await sleeps.next())
        harness.clock.advance(by: .milliseconds(180))
        harness.refresh.cancel()
        #expect(!harness.isPending)
        harness.refresh.schedule(.geometryChanged)
        #expect(await sleeps.next() == .milliseconds(200))
        harness.clock.advance(by: .milliseconds(200))
        _ = try #require(await publications.next())
        #expect(harness.readCount == 1)
    }

    @Test("A burst of settled geometry events performs one current read")
    func geometryBurstCoalescesWithoutStarvation() async throws {
        let harness = GeometryRefreshHarness()
        defer { harness.close() }
        var sleeps = harness.clock.requests.makeAsyncIterator()
        var publications = harness.publications.makeAsyncIterator()

        harness.refresh.schedule(.geometryChanged)
        _ = try #require(await sleeps.next())
        for remaining in stride(from: 180, through: 20, by: -20) {
            harness.clock.advance(by: .milliseconds(20))
            harness.refresh.schedule(.geometryChanged)
            #expect(await sleeps.next() == .milliseconds(remaining))
        }
        harness.clock.advance(by: .milliseconds(20))
        _ = try #require(await publications.next())
        #expect(harness.readCount == 1)
        #expect(harness.publishedSnapshots.count == 1)
    }
}

@MainActor
private final class GeometryRefreshHarness {
    let clock = GeometryRefreshClock()
    var value = MenuBarGeometryRefresh.Snapshot(
        itemBounds: [CGRect(x: 100, y: 0, width: 24, height: 30)],
        chevronFrame: .zero
    )
    var readCount = 0
    var readRequirements: [ContinuousClock.Instant?] = []
    var isPending = false
    var pendingChanges: [Bool] = []
    var publishedSnapshots: [MenuBarGeometryRefresh.Snapshot] = []
    var readOperation: (() async -> MenuBarGeometryRefresh.Snapshot?)?
    let publications: AsyncStream<MenuBarGeometryRefresh.Snapshot>
    private let publishContinuation: AsyncStream<MenuBarGeometryRefresh.Snapshot>.Continuation
    let completions: AsyncStream<Void>
    private let completionContinuation: AsyncStream<Void>.Continuation

    init() {
        (publications, publishContinuation) = AsyncStream.makeStream()
        (completions, completionContinuation) = AsyncStream.makeStream()
    }

    lazy var refresh = MenuBarGeometryRefresh(
        read: { [weak self] minimumReadTime in
            guard let self else { return nil }
            readCount += 1
            readRequirements.append(minimumReadTime)
            value.readAt = clock.now
            if let readOperation {
                return await readOperation()
            }
            return value
        },
        publish: { [weak self] snapshot in
            self?.publishedSnapshots.append(snapshot)
            self?.publishContinuation.yield(snapshot)
        },
        setPending: { [weak self] pending in
            self?.isPending = pending
            self?.pendingChanges.append(pending)
            if !pending { self?.completionContinuation.yield() }
        },
        now: { [clock] in clock.now },
        sleep: { [clock] in try await clock.sleep(for: $0) }
    )

    func close() {
        refresh.cancel()
        readOperation = nil
        clock.close()
        publishContinuation.finish()
        completionContinuation.finish()
    }
}

@MainActor
private final class GeometryReadGate {
    let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private var continuation: CheckedContinuation<MenuBarGeometryRefresh.Snapshot?, Never>?

    init() {
        (started, startedContinuation) = AsyncStream.makeStream()
    }

    func read() async -> MenuBarGeometryRefresh.Snapshot? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            startedContinuation.yield()
        }
    }

    func resume(_ snapshot: MenuBarGeometryRefresh.Snapshot?) {
        continuation?.resume(returning: snapshot)
        continuation = nil
    }
}

/// Cancellation deliberately does not resume a sleeper: old work can finish
/// after its replacement, as an AX read that ignores cancellation can do.
@MainActor
private final class GeometryRefreshClock {
    var now = ContinuousClock.now
    let requests: AsyncStream<Duration>
    private let requestContinuation: AsyncStream<Duration>.Continuation
    private var sleepers: [(ContinuousClock.Instant, CheckedContinuation<Void, any Error>)] = []
    var nextWake: ContinuousClock.Instant? { sleepers.map(\.0).min() }

    init() {
        (requests, requestContinuation) = AsyncStream.makeStream()
    }

    func sleep(for delay: Duration) async throws {
        requestContinuation.yield(delay)
        guard delay > .zero else { return }
        try await withCheckedThrowingContinuation { continuation in
            sleepers.append((now.advanced(by: delay), continuation))
        }
    }

    func advance(by duration: Duration) {
        now = now.advanced(by: duration)
        let ready = sleepers.filter { $0.0 <= now }
        sleepers.removeAll { $0.0 <= now }
        for (_, continuation) in ready {
            continuation.resume()
        }
    }

    func close() {
        for (_, continuation) in sleepers {
            continuation.resume(throwing: CancellationError())
        }
        sleepers.removeAll()
        requestContinuation.finish()
    }
}
