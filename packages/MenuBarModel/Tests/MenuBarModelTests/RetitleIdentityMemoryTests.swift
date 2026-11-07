//
//  RetitleIdentityMemoryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

/// An item that reads with its identifier most of the time keeps that identity on a read that misses it.
@Suite("Retitle identity memory")
struct RetitleIdentityMemoryTests {
    private typealias Slot = RetitleIdentityMemory.Slot

    /// #1489: Raycast's calendar item is "calendar-events" with titles like "Standup • in 52m".
    @Test("A read that falls back to the title keeps the slot's last stable identity")
    func titleFallbackKeepsTheIdentity() {
        var memory = RetitleIdentityMemory()
        #expect(memory.resolve(owner: 7, slots: [Slot("calendar-events", isStable: true), Slot("clipboard", isStable: true)])
            == ["calendar-events", "clipboard"])
        #expect(memory.resolve(owner: 7, slots: [Slot("Standup • in 52m", isStable: false), Slot("clipboard", isStable: true)])
            == ["calendar-events", "clipboard"])
        #expect(memory.resolve(owner: 7, slots: [Slot("Standup • in 51m", isStable: false), Slot("clipboard", isStable: true)])
            == ["calendar-events", "clipboard"], "the kept identity carries over to the next fallback")
    }

    @Test("A different number of items, another process or no earlier stable read leaves titles alone")
    func refusesWhenTheSlotsDontLineUp() {
        var memory = RetitleIdentityMemory()
        _ = memory.resolve(owner: 7, slots: [Slot("calendar-events", isStable: true)])
        #expect(memory.resolve(owner: 7, slots: [Slot("Standup", isStable: false), Slot("new", isStable: true)]) == ["Standup", "new"])
        #expect(memory.resolve(owner: 8, slots: [Slot("Standup", isStable: false)]) == ["Standup"])

        var fresh = RetitleIdentityMemory()
        _ = fresh.resolve(owner: 7, slots: [Slot("Standup", isStable: false)])
        #expect(fresh.resolve(owner: 7, slots: [Slot("Review", isStable: false)]) == ["Review"])
    }

    @Test("An identity another slot already has is not given out twice")
    func noDuplicateIdentities() {
        var memory = RetitleIdentityMemory()
        _ = memory.resolve(owner: 7, slots: [Slot("a", isStable: true), Slot("b", isStable: true)])
        #expect(memory.resolve(owner: 7, slots: [Slot("b", isStable: true), Slot("Title", isStable: false)]) == ["b", "Title"])
    }

    @Test("The memory keeps a bounded number of processes, dropping the oldest")
    func boundedByOwner() {
        var memory = RetitleIdentityMemory(capacity: 2)
        _ = memory.resolve(owner: 1, slots: [Slot("one", isStable: true)])
        _ = memory.resolve(owner: 2, slots: [Slot("two", isStable: true)])
        _ = memory.resolve(owner: 3, slots: [Slot("three", isStable: true)])
        #expect(memory.resolve(owner: 1, slots: [Slot("Title", isStable: false)]) == ["Title"])
        #expect(memory.resolve(owner: 3, slots: [Slot("Title", isStable: false)]) == ["three"])
    }
}
