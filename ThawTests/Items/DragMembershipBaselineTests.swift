//
//  DragMembershipBaselineTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Drag membership baseline")
struct DragMembershipBaselineTests {
    private final class Reads {
        var values = [Int]()
        var cancels = 0
    }

    private func holder(reading values: [Int?]) -> (DragMembershipBaseline<Int>, Reads) {
        let holder = DragMembershipBaseline<Int>()
        let reads = Reads()
        var queue = values
        holder.read = {
            let next = queue.isEmpty ? nil : queue.removeFirst()
            if let next { reads.values.append(next) }
            return next
        }
        holder.cancelPendingRead = { reads.cancels += 1 }
        return (holder, reads)
    }

    @Test("A drag records what the weights read as when it starts")
    func recordsAtStart() {
        let (holder, reads) = holder(reading: [1])
        holder.dragStarted()
        #expect(holder.baseline == 1)
        #expect(reads.cancels == 1)
    }

    @Test("A second drag before the read keeps the first drag's baseline and cancels the waiting read")
    func secondDragKeepsTheFirst() {
        let (holder, reads) = holder(reading: [1, 2])
        holder.dragStarted()
        holder.dragStarted()
        #expect(holder.baseline == 1)
        #expect(reads.values == [1])
        #expect(reads.cancels == 2)
    }

    @Test("Clearing lets the next drag take a fresh baseline")
    func clearingStartsOver() {
        let (holder, _) = holder(reading: [1, 2])
        holder.dragStarted()
        holder.clear()
        #expect(holder.baseline == nil)
        holder.dragStarted()
        #expect(holder.baseline == 2)
    }

    @Test("A drag whose weights can't be read leaves no baseline, and the next drag tries again")
    func unreadableStart() {
        let (holder, _) = holder(reading: [nil, 3])
        holder.dragStarted()
        #expect(holder.baseline == nil)
        holder.dragStarted()
        #expect(holder.baseline == 3)
    }

    @Test("Successive drags collect the items grabbed, and clearing forgets them")
    func collectsPressedItems() {
        let (holder, _) = holder(reading: [1])
        let first = MenuBarItemTag(namespace: .string("com.example.first"), title: "Item-0", instanceIndex: 0)
        let second = MenuBarItemTag(namespace: .string("com.example.second"), title: "Item-0", instanceIndex: 0)
        holder.dragStarted(pressing: first)
        holder.dragStarted(pressing: second)
        #expect(holder.pressed == [first, second])
        holder.clear()
        #expect(holder.pressed == [])
    }

    @Test("A drag on an item that couldn't be named leaves every crossing item eligible")
    func unnamedPressAllowsAll() {
        let (holder, _) = holder(reading: [1])
        holder.dragStarted(pressing: MenuBarItemTag(namespace: .string("com.example.first"), title: "Item-0", instanceIndex: 0))
        holder.dragStarted()
        #expect(holder.pressed == nil)
    }
}
