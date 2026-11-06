//
//  MoveFailureMemoryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("A section-order drag that keeps failing is left alone for a while")
struct MoveFailureMemoryTests {
    private let start = ContinuousClock.now
    private let a = Self.item("A", x: 0)
    private let b = Self.item("B", x: 30)
    private let c = Self.item("C", x: 60)

    private var order: [String] {
        [a, b, c].map(\.uniqueIdentifier)
    }

    @Test("The third failure in a row trips the item breaker")
    func thirdFailureTrips() {
        var memory = MoveFailureMemory()
        let move = MoveFailureMemory.Move(item: a, destination: .rightOfItem(c))

        memory.recordFailure(of: move, desiredOrder: order, now: start)
        memory.recordFailure(of: move, desiredOrder: order, now: start + .seconds(1))
        #expect(!memory.isBreakerTripped(for: move, now: start + .seconds(1)))
        #expect(memory.failureCount(for: move) == 2)

        memory.recordFailure(of: move, desiredOrder: order, now: start + .seconds(2))
        #expect(memory.isBreakerTripped(for: move, now: start + .seconds(2)))
        #expect(memory.failureCount(for: move) == 3)
    }

    @Test("A tripped breaker holds for its cooldown and then lets the move through")
    func breakerLapses() {
        var memory = MoveFailureMemory()
        let move = MoveFailureMemory.Move(item: a, destination: .rightOfItem(c))
        for _ in 0 ..< MoveFailureMemory.itemFailureThreshold {
            memory.recordFailure(of: move, desiredOrder: order, now: start)
        }

        let cooldown = MoveFailureMemory.itemFailureCooldown
        #expect(memory.isBreakerTripped(for: move, now: start + cooldown - .seconds(1)))
        #expect(!memory.isBreakerTripped(for: move, now: start + cooldown))
    }

    @Test("A gap past the cooldown restarts the streak")
    func gapRestartsTheStreak() {
        var memory = MoveFailureMemory()
        let move = MoveFailureMemory.Move(item: a, destination: .rightOfItem(c))
        let later = start + MoveFailureMemory.itemFailureCooldown

        memory.recordFailure(of: move, desiredOrder: order, now: start)
        memory.recordFailure(of: move, desiredOrder: order, now: start)
        memory.recordFailure(of: move, desiredOrder: order, now: later)

        #expect(memory.failureCount(for: move) == 1)
        #expect(!memory.isBreakerTripped(for: move, now: later))
    }

    @Test("A move that lands clears both memories")
    func successClearsBoth() {
        var memory = MoveFailureMemory()
        let move = MoveFailureMemory.Move(item: a, destination: .rightOfItem(c))
        for _ in 0 ..< MoveFailureMemory.itemFailureThreshold {
            memory.recordFailure(of: move, desiredOrder: order, now: start)
        }

        memory.recordSuccess(of: move, desiredOrder: order)

        #expect(memory.failureCount(for: move) == 0)
        #expect(!memory.isBreakerTripped(for: move, now: start))
        #expect(!memory.isBackingOff(from: move, desiredOrder: order, now: start))
    }

    @Test("The item breaker ignores the desired order; the backoff does not")
    func itemKeyIgnoresTheDesiredOrder() {
        var memory = MoveFailureMemory()
        let move = MoveFailureMemory.Move(item: a, destination: .rightOfItem(c))
        let orders = [order, order.reversed(), [order[1], order[0], order[2]]]

        for (offset, desired) in orders.enumerated() {
            #expect(!memory.isBackingOff(from: move, desiredOrder: desired, now: start))
            memory.recordFailure(of: move, desiredOrder: desired, now: start + .seconds(offset))
        }

        #expect(memory.isBreakerTripped(for: move, now: start + .seconds(2)))
    }

    @Test("The item, the side and the target each tell moves apart")
    func movesAreToldApart() {
        var memory = MoveFailureMemory()
        let move = MoveFailureMemory.Move(item: a, destination: .rightOfItem(c))
        for _ in 0 ..< MoveFailureMemory.itemFailureThreshold {
            memory.recordFailure(of: move, desiredOrder: order, now: start)
        }

        let others = [
            MoveFailureMemory.Move(item: b, destination: .rightOfItem(c)),
            MoveFailureMemory.Move(item: a, destination: .leftOfItem(c)),
            MoveFailureMemory.Move(item: a, destination: .rightOfItem(b)),
        ]
        for other in others {
            #expect(!memory.isBreakerTripped(for: other, now: start))
            #expect(!memory.isBackingOff(from: other, desiredOrder: order, now: start))
        }
    }

    @Test("One failure backs the move off for the window, and then it lapses")
    func backoffHoldsAndLapses() {
        var memory = MoveFailureMemory()
        let move = MoveFailureMemory.Move(item: a, destination: .leftOfItem(b))

        #expect(!memory.isBackingOff(from: move, desiredOrder: order, now: start))
        memory.recordFailure(of: move, desiredOrder: order, now: start)

        let backoff = MoveFailureMemory.backoff
        #expect(memory.isBackingOff(from: move, desiredOrder: order, now: start))
        #expect(memory.isBackingOff(from: move, desiredOrder: order, now: start + backoff - .seconds(1)))
        #expect(!memory.isBackingOff(from: move, desiredOrder: order, now: start + backoff))
    }

    @Test("Backing off without a failed drag leaves the item breaker alone")
    func backOffAloneDoesNotCount() {
        var memory = MoveFailureMemory()
        let move = MoveFailureMemory.Move(item: a, destination: .leftOfItem(b))

        memory.backOff(from: move, desiredOrder: order, now: start)

        #expect(memory.isBackingOff(from: move, desiredOrder: order, now: start))
        #expect(memory.failureCount(for: move) == 0)
    }

    @Test("The windows and the limit are the ones the manager used")
    func constants() {
        #expect(MoveFailureMemory.backoff == .seconds(30))
        #expect(MoveFailureMemory.itemFailureThreshold == 3)
        #expect(MoveFailureMemory.itemFailureCooldown == .seconds(30))
    }

    private static func item(_ title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: UInt32(x) + 1,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }
}
