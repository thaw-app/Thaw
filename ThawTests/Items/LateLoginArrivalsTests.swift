//
//  LateLoginArrivalsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// A few looks after launch catch login items that add their icons late, and do nothing when none did.
@MainActor
@Suite("Late login arrivals")
struct LateLoginArrivalsTests {
    @Test("The looks land at 20, 40, 60 and 90 s after launch")
    func waitsFromLaunch() {
        #expect(LateLoginArrivals.waits(sinceLaunch: .zero) == [.seconds(20), .seconds(20), .seconds(20), .seconds(30)])
        #expect(LateLoginArrivals.waits(sinceLaunch: .seconds(12)) == [.seconds(8), .seconds(20), .seconds(20), .seconds(30)])
    }

    @Test("Looks whose time has passed are dropped")
    func passedLooksDropped() {
        #expect(LateLoginArrivals.waits(sinceLaunch: .seconds(45)) == [.seconds(15), .seconds(30)])
        #expect(LateLoginArrivals.waits(sinceLaunch: .seconds(90)).isEmpty)
    }

    @Test("Only a different set of items counts as a change, not another order")
    func itemSetChange() {
        #expect(!LateLoginArrivals.itemSetChanged(cached: ["a", "b"], current: ["b", "a"]))
        #expect(LateLoginArrivals.itemSetChanged(cached: ["a", "b"], current: ["a", "b", "c"]))
        #expect(LateLoginArrivals.itemSetChanged(cached: ["a", "b"], current: ["a"]))
    }

    @Test("A look settles only when the item set changed")
    func settlesOnlyOnChange() async {
        var looks = 0
        var settles = 0
        var slept = [Duration]()
        let readings: [(cached: [String], current: [String])?] = [(["a"], ["a"]), (["a"], ["a", "late"]), nil, (["a", "late"], ["late", "a"])]
        let settled = await LateLoginArrivals.run(
            waits: [.seconds(20), .seconds(20), .seconds(20), .seconds(30)],
            sleep: { slept.append($0) },
            read: {
                defer { looks += 1 }
                return readings[looks]
            },
            settle: { settles += 1 }
        )
        #expect(settled == 1)
        #expect(settles == 1)
        #expect(looks == 4)
        #expect(slept == [.seconds(20), .seconds(20), .seconds(20), .seconds(30)])
    }

    @Test("Cancelling the wait ends the looks")
    func cancelledWaitEnds() async {
        struct Cancelled: Error {}
        var looks = 0
        let settled = await LateLoginArrivals.run(
            waits: [.seconds(20), .seconds(20)],
            sleep: { _ in throw Cancelled() },
            read: {
                looks += 1
                return (["a"], ["b"])
            },
            settle: {}
        )
        #expect(settled == 0)
        #expect(looks == 0)
    }

    @Test("Scheduled long after launch, nothing is left to look at")
    func scheduledLate() async {
        let task = LateLoginArrivals.schedule(for: MenuBarItemManager(), launchedAt: Date.now.addingTimeInterval(-600))
        await task.value
    }
}
