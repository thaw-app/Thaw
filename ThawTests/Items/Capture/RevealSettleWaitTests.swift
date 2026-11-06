//
//  RevealSettleWaitTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Reveal settle waits", .timeLimit(.minutes(1)))
struct RevealSettleWaitTests {
    private typealias Session = RevealCaptureSession

    private static func item(_ title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.settle"), title: title, windowID: 7, instanceIndex: 0),
            windowID: 7,
            ownerPID: 501,
            sourcePID: 501,
            bounds: CGRect(x: x, y: 0, width: 24, height: 22),
            title: title,
            isOnScreen: true
        )
    }

    private static func settleClock(_ clock: TestClock) -> Session.SettleClock {
        Session.SettleClock(now: { clock.now }, sleep: { try? await clock.sleep(for: $0) })
    }

    @Test("Members that hold still for one poll settle, paired with their request in request order")
    func membersSettle() async {
        let clock = TestClock()
        let first = Self.item("First", x: 1000), second = Self.item("Second", x: 1100)
        var reads = 0
        let pairs = await Session.waitForRevealedItems(matching: [first, second], clock: Self.settleClock(clock)) {
            reads += 1
            return [second, first]
        }
        #expect(pairs.map(\.requested.tag) == [first.tag, second.tag])
        #expect(pairs.map(\.live.tag) == [first.tag, second.tag])
        #expect(reads == 2)
    }

    @Test("A member that never appears is left out after the last poll")
    func missingMemberIsLeftOut() async {
        let clock = TestClock()
        let shown = Self.item("Shown", x: 1000), missing = Self.item("Missing", x: 1100)
        var reads = 0
        let pairs = await Session.waitForRevealedItems(matching: [shown, missing], clock: Self.settleClock(clock)) {
            reads += 1
            return [shown]
        }
        #expect(pairs.map(\.requested.tag) == [shown.tag])
        #expect(reads == 20)
    }

    @Test("The settle budget ends the polls when reads are slow")
    func budgetEndsThePolls() async {
        let clock = TestClock()
        let moving = Self.item("Moving", x: 1000)
        var reads = 0
        let pairs = await Session.waitForRevealedItems(matching: [moving], clock: Self.settleClock(clock)) {
            reads += 1
            clock.now = clock.now.advanced(by: .seconds(1))
            return [Self.item("Moving", x: 1000 + CGFloat(reads) * 50)]
        }
        #expect(pairs.isEmpty)
        #expect(reads == 3)
    }

    @Test("Nothing requested, or a cancelled wait, reads nothing")
    func emptyOrCancelledReadsNothing() async {
        var reads = 0
        #expect(await Session.waitForRevealedItems(matching: []) {
            reads += 1
            return []
        }.isEmpty)

        let item = Self.item("Cancelled", x: 1000)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await Session.waitForRevealedItems(matching: [item]) {
                reads += 1
                return [item]
            }
        }
        #expect(await task.value.isEmpty)
        #expect(reads == 0)
    }

    @Test("Pixels that keep changing run the injected clock out to the budget")
    func pixelBudgetOnTheInjectedClock() async {
        let clock = TestClock()
        let start = clock.now
        var value: UInt8 = 0
        let settled = await Session.waitForSettledPixels(minimumSettle: .zero, budget: .seconds(1), clock: Self.settleClock(clock)) {
            value &+= 1
            return [Data([value])]
        }
        #expect(!settled)
        #expect(value == 10)
        #expect(clock.now - start == .seconds(1))
    }

    @Test("A revealed batch whose pixels hold still settles after three matching screenshots")
    func revealedPixelsSettle() async throws {
        let clock = TestClock()
        let reader = try CaptureFixture(hosting: CaptureFixture.barCapture(opaque: false, glyphXs: [1008]), strip: nil)
        await Session.settleRevealedPixels([Self.item("Still", x: 1000)], displayID: 42, reader: reader, clock: Self.settleClock(clock))
        #expect(await reader.captures == [.hosting, .hosting, .hosting])
    }
}
