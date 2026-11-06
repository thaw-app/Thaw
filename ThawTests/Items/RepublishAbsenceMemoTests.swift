//
//  RepublishAbsenceMemoTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("A Visible member that did not republish is not waited for again until the memory lapses")
struct RepublishAbsenceMemoTests {
    private let start = ContinuousClock.now

    @Test("A new memo knows of no absentee")
    func startsEmpty() {
        let memo = RepublishAbsenceMemo()

        #expect(memo.isEmpty)
        #expect(memo.isEmpty)
        #expect(!memo.isKnownAbsent("a"))
    }

    @Test("A member stamped missing is known absent, and the others are not")
    func missingIsRemembered() {
        var memo = RepublishAbsenceMemo()

        memo.noteMissing(["a", "b"], at: start)

        #expect(memo.isKnownAbsent("a"))
        #expect(memo.isKnownAbsent("b"))
        #expect(!memo.isKnownAbsent("c"))
        #expect(memo.count == 2)
    }

    @Test("An entry lasts until the memory window has passed")
    func entriesExpireAfterTheMemoryWindow() {
        var memo = RepublishAbsenceMemo()
        memo.noteMissing(["a"], at: start)

        memo.expire(now: start + RepublishAbsenceMemo.memory - .milliseconds(1))
        #expect(memo.isKnownAbsent("a"))

        memo.expire(now: start + RepublishAbsenceMemo.memory)
        #expect(!memo.isKnownAbsent("a"))
        #expect(memo.isEmpty)
    }

    @Test("Expiry drops the old entries and keeps the recent ones")
    func expiryIsPerEntry() {
        var memo = RepublishAbsenceMemo()
        memo.noteMissing(["old"], at: start)
        memo.noteMissing(["recent"], at: start + .seconds(5))

        memo.expire(now: start + .seconds(10))

        #expect(!memo.isKnownAbsent("old"))
        #expect(memo.isKnownAbsent("recent"))
    }

    @Test("Missing again restarts that member's window")
    func missingAgainRestartsTheWindow() {
        var memo = RepublishAbsenceMemo()
        memo.noteMissing(["a"], at: start)
        memo.noteMissing(["a"], at: start + .seconds(8))

        memo.expire(now: start + .seconds(12))

        #expect(memo.isKnownAbsent("a"))
    }

    @Test("An arrival clears that member and leaves the others")
    func arrivalClears() {
        var memo = RepublishAbsenceMemo()
        memo.noteMissing(["a", "b"], at: start)

        memo.noteArrived(["a", "never missing"])

        #expect(!memo.isKnownAbsent("a"))
        #expect(memo.isKnownAbsent("b"))
        #expect(memo.count == 1)
    }

    @Test("Forgetting empties it")
    func forgetEmpties() {
        var memo = RepublishAbsenceMemo()
        memo.noteMissing(["a", "b"], at: start)

        memo.forget()

        #expect(memo.isEmpty)
        #expect(!memo.isKnownAbsent("a"))
    }

    @Test("The memory window is ten seconds")
    func memoryWindow() {
        #expect(RepublishAbsenceMemo.memory == .seconds(10))
    }

    @Test
    func anEmptyReadNamesNoAbsentees() {
        #expect(RepublishAbsenceMemo.absentees(wanted: ["a", "b"], live: []).isEmpty)
    }

    @Test
    func aReadWithItemsNamesTheWantedMembersItLacks() {
        #expect(RepublishAbsenceMemo.absentees(wanted: ["a", "b"], live: ["a", "c"]) == ["b"])
    }

    @Test("A member whose app is neither running nor on the bar cannot republish")
    func unreachableNeedsNoRunningAppAndNoLiveItem() {
        let unreachable = RepublishAbsenceMemo.unreachable(
            wanted: ["com.old.floe:Floe", "com.example.launching:Item-0", "com.apple.MenuBarAgent:com.apple.menuextra.wifi", "com.example.live:Second"],
            liveNamespaces: ["com.apple.MenuBarAgent", "com.example.live"],
            runningBundleIDs: ["com.example.launching", "com.example.live"]
        )

        #expect(unreachable == ["com.old.floe:Floe"], "A running app may still publish, and a live app's item may still return")
    }

    @Test("An item that is not named by an app's bundle is still waited for")
    func nonBundleNamespacesStayAwaited() {
        let unreachable = RepublishAbsenceMemo.unreachable(
            wanted: ["null:Item-0", "8A1F3E7C-2B4D-4E5F-9A6B-7C8D9E0F1A2B:Item-0"],
            liveNamespaces: [],
            runningBundleIDs: []
        )

        #expect(unreachable.isEmpty)
    }
}
