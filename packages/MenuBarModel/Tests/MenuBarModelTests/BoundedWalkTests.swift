//
//  BoundedWalkTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

/// Counts jobs running at once.
private actor InFlight {
    private(set) var current = 0
    private(set) var peak = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func leave() {
        current -= 1
    }
}

@Suite("Bounded walk")
struct BoundedWalkTests {
    @Test("No more than the limit run at once, and every job's answer is collected")
    func limitsConcurrencyAndCollectsAll() async {
        let inFlight = InFlight()
        var collected: [Int] = []
        await BoundedWalk.run(Array(0 ..< 20), limit: 4) { item in
            .run {
                await inFlight.enter()
                try? await Task.sleep(for: .milliseconds(10))
                await inFlight.leave()
                return item
            }
        } collect: { collected.append($0) }

        #expect(collected.sorted() == Array(0 ..< 20))
        #expect(await inFlight.peak <= 4)
        #expect(await inFlight.peak > 1)
    }

    @Test("A skipped item runs nothing, and stop starts nothing more but collects what is running")
    func skipAndStop() async {
        var started: [Int] = []
        var collected: [Int] = []
        await BoundedWalk.run(Array(0 ..< 10), limit: 3) { item in
            if item == 1 { return .skip }
            if item == 5 { return .stop }
            started.append(item)
            return .run { item }
        } collect: { collected.append($0) }

        #expect(started == [0, 2, 3, 4])
        #expect(collected.sorted() == [0, 2, 3, 4])
    }

    @Test("An item is only considered once a slot is free, so its checks see the time it would start")
    func startWaitsForAFreeSlot() async {
        let inFlight = InFlight()
        var busyAtStart: [Int] = []
        await BoundedWalk.run(Array(0 ..< 8), limit: 2) { item in
            await busyAtStart.append(inFlight.current)
            return .run {
                await inFlight.enter()
                try? await Task.sleep(for: .milliseconds(5))
                await inFlight.leave()
                return item
            }
        } collect: { _ in }

        #expect(busyAtStart.allSatisfy { $0 < 2 })
    }
}
