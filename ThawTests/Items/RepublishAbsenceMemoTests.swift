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

    @Test("A left-out member is still watched for after the ten-second memory lapses")
    func leftOutOutlastsTheMemory() {
        var memo = RepublishAbsenceMemo()
        memo.noteMissing(["istat"], at: start)
        let later = start + .seconds(30)

        memo.expire(now: later)

        #expect(!memo.isKnownAbsent("istat"), "Passes stop waiting for it")
        #expect(memo.hasLeftOutMembers(now: later))
        #expect(memo.leftOutMembers(amongLive: ["istat", "battery"], now: later) == ["istat"])
    }

    @Test("A member left out two minutes ago is no longer watched for")
    func leftOutExpires() {
        var memo = RepublishAbsenceMemo()
        memo.noteMissing(["a"], at: start)
        let lapsed = start + RepublishAbsenceMemo.leftOutMemory

        #expect(memo.hasLeftOutMembers(now: lapsed - .milliseconds(1)))
        #expect(!memo.hasLeftOutMembers(now: lapsed))
        #expect(memo.leftOutMembers(amongLive: ["a"], now: lapsed).isEmpty)

        memo.expire(now: lapsed)
        #expect(!memo.hasLeftOutMembers(now: start))
    }

    @Test("Only the left-out members that are live are named")
    func onlyLiveLeftOutMembersAreNamed() {
        var memo = RepublishAbsenceMemo()
        memo.noteMissing(["a", "b"], at: start)

        #expect(memo.leftOutMembers(amongLive: ["a", "c"], now: start) == ["a"])
        #expect(memo.leftOutMembers(amongLive: [], now: start).isEmpty)
    }

    @Test("A pass that sees a left-out member live places it, so it is no longer watched for")
    func arrivalClearsLeftOut() {
        var memo = RepublishAbsenceMemo()
        memo.noteMissing(["a", "b"], at: start)

        memo.noteArrived(["a"])

        #expect(memo.leftOutMembers(amongLive: ["a", "b"], now: start) == ["b"])
        memo.noteArrived(["b"])
        #expect(!memo.hasLeftOutMembers(now: start))
    }

    @Test("Forgetting the absences keeps left-out members watched")
    func forgetKeepsLeftOut() {
        var memo = RepublishAbsenceMemo()
        memo.noteMissing(["a"], at: start)

        memo.forget()

        #expect(memo.isEmpty)
        #expect(memo.hasLeftOutMembers(now: start))
    }

    @Test("Each watch gets its own generation")
    func watchGenerationsCount() {
        var memo = RepublishAbsenceMemo()

        #expect(memo.watchGeneration == 0)
        #expect(memo.startWatch() == 1)
        #expect(memo.startWatch() == 2)
        #expect(memo.watchGeneration == 2)
    }

    @Test("A left-out member is watched for two minutes")
    func leftOutWindow() {
        #expect(RepublishAbsenceMemo.leftOutMemory == .seconds(120))
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

    @Test("Only members whose app runs or has an item live are worth a warning, a stopped Thaw extra included")
    func reportableSkipsStoppedApps() {
        let reportable = RepublishAbsenceMemo.reportable(
            ["com.old.floe:Floe", "com.stonerl.Thaw.extra.focus:Thaw.Extra.Focus", "com.stonerl.Thaw.extra.timer:Thaw.Extra.Timer",
             "com.example.running:Item-0", "com.example.live:Second", "null:Item-0"],
            liveNamespaces: ["com.example.live"],
            runningBundleIDs: ["com.stonerl.Thaw", "com.stonerl.Thaw.extra.timer", "com.example.running"]
        )

        #expect(reportable == ["com.stonerl.Thaw.extra.timer:Thaw.Extra.Timer", "com.example.running:Item-0", "com.example.live:Second", "null:Item-0"])
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

    @Test("A pass that sees members records when, and one that saw none leaves it alone")
    func lastSawMembers() {
        var memo = RepublishAbsenceMemo()
        #expect(memo.lastSawMembers == nil)

        memo.noteArrived([String](), at: start)
        #expect(memo.lastSawMembers == nil)

        memo.noteArrived(["a"], at: start + .seconds(2))
        #expect(memo.lastSawMembers == start + .seconds(2))
        memo.noteArrived([String](), at: start + .seconds(4))
        #expect(memo.lastSawMembers == start + .seconds(2))
    }

    @Test("A pass that took its order earlier but finishes later doesn't move the sighting back")
    func lastSawMembersKeepsTheLatest() {
        var memo = RepublishAbsenceMemo()
        memo.noteArrived(["a"], at: start + .seconds(5))

        memo.noteArrived(["a"], at: start + .seconds(1))

        #expect(memo.lastSawMembers == start + .seconds(5))
    }

    @Test("A pass that took its order before a member was left out can't forget it; a later pass can")
    func olderPassKeepsANewerOmission() {
        var memo = RepublishAbsenceMemo()
        memo.noteMissing(["a"], at: start + .seconds(5))

        memo.noteArrived(["a"], at: start + .seconds(1))
        #expect(memo.isKnownAbsent("a"))
        #expect(memo.leftOutMembers(amongLive: ["a"], now: start + .seconds(6)) == ["a"])

        memo.noteArrived(["a"], at: start + .seconds(6))
        #expect(!memo.isKnownAbsent("a"))
        #expect(!memo.hasLeftOutMembers(now: start + .seconds(6)))
    }

    @Test("Restores asked for a member hold it back at the limit, survive being left out again, and clear once it is placed")
    func restoreCountsLastUntilPlaced() {
        var memo = RepublishAbsenceMemo()
        memo.noteMissing(["a", "b"], at: start)

        memo.noteRestoreAsked(for: ["a"])
        memo.noteRestoreAsked(for: ["a"])
        memo.noteMissing(["a"], at: start + .seconds(1))

        #expect(memo.restoresAsked(for: "a") == 2)
        #expect(memo.leftOutMembers(amongLive: ["a", "b"], restoreLimit: 2, now: start + .seconds(2)) == ["b"])
        #expect(memo.leftOutMembers(amongLive: ["a", "b"], restoreLimit: 3, now: start + .seconds(2)) == ["a", "b"])

        memo.noteArrived(["a"], at: start + .seconds(2))
        #expect(memo.restoresAsked(for: "a") == 0)
    }

    @Test("Only a left-out member still in Visible waits, when the Visible members are known")
    func leftOutCountsOnlyVisibleMembers() {
        var memo = RepublishAbsenceMemo()
        memo.noteMissing(["moved"], at: start)

        #expect(memo.hasLeftOutMembers(now: start))
        #expect(!memo.hasLeftOutMembers(among: ["a", "b"], now: start))
        #expect(memo.hasLeftOutMembers(among: ["a", "moved"], now: start))
    }

    @Test("Every member left out within the window is still waiting, whichever pass left it out")
    func leftOutIdentifiersSpanPasses() {
        var memo = RepublishAbsenceMemo()
        memo.noteMissing(["older"], at: start)
        memo.noteMissing(["newer"], at: start + .seconds(5))

        #expect(memo.leftOutIdentifiers(now: start + .seconds(6)) == ["older", "newer"])
        #expect(memo.leftOutIdentifiers(now: start + RepublishAbsenceMemo.leftOutMemory + .seconds(1)) == ["newer"])
    }

    @Test("Restore counts lapse with the left-out window")
    func restoreCountsExpire() {
        var memo = RepublishAbsenceMemo()
        memo.noteMissing(["a"], at: start)
        memo.noteRestoreAsked(for: ["a"])

        memo.expire(now: start + RepublishAbsenceMemo.leftOutMemory)

        #expect(memo.restoresAsked(for: "a") == 0)
    }
}
