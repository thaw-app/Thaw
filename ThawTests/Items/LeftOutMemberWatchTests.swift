//
//  LeftOutMemberWatchTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// 2026-11-05: after a restart, iStat Menus' item appeared after the visible pass stopped waiting
/// for it. The pass placed the rest without it, and the item stayed next to Thaw's icon until
/// Thaw was relaunched.
@MainActor
@Suite("A Visible member left out of a pass is placed once it shows up")
struct LeftOutMemberWatchTests {
    private typealias Situation = LeftOutMemberWatch.Situation

    private static let arrived = Situation(liveLeftOutMembers: ["istat"])

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

    @Test("A left-out member on the bar is placed")
    func arrivalIsRestored() {
        #expect(LeftOutMemberWatch.step(Self.arrived) == .restore(["istat"]))
    }

    @Test("The watch keeps waiting while no left-out member is on the bar")
    func waitsForTheArrival() {
        #expect(LeftOutMemberWatch.step(Situation()) == .wait)
    }

    @Test("The watch waits while something else is arranging the bar", arguments: [
        Situation(liveLeftOutMembers: ["istat"], isUserArranging: true),
        Situation(liveLeftOutMembers: ["istat"], isLayoutBeingApplied: true),
        Situation(liveLeftOutMembers: ["istat"], isSectionRevealed: true),
        Situation(liveLeftOutMembers: ["istat"], isOrderApplyPending: true),
        Situation(liveLeftOutMembers: ["istat"], isWithinRestrictionSettleWindow: true),
    ])
    func waitsWhileBusy(_ situation: LeftOutMemberWatch.Situation) {
        #expect(LeftOutMemberWatch.step(situation) == .wait)
    }

    @Test("The watch stops once it has no reason to place anything", arguments: [
        Situation(isCurrentWatch: false, liveLeftOutMembers: ["istat"]),
        Situation(hasLeftOutMembers: false, liveLeftOutMembers: ["istat"]),
        Situation(liveLeftOutMembers: ["istat"], arrangementIsManual: true),
        Situation(liveLeftOutMembers: ["istat"], userDraggedSinceStart: true),
    ])
    func stops(_ situation: LeftOutMemberWatch.Situation) {
        #expect(LeftOutMemberWatch.step(situation) == .stop)
    }

    @Test("Looks continue until the member shows up, and stop once a pass placed it")
    func restoresOnceAfterWaiting() async {
        var pending = Situation(liveLeftOutMembers: ["istat"])
        pending.isOrderApplyPending = true
        let placed = Situation(hasLeftOutMembers: false)
        var looks = [Situation(), Situation(), Self.arrived, pending, placed, Self.arrived]
        var slept = [Duration]()
        var restored = [Set<String>]()

        let restores = await LeftOutMemberWatch.run(
            sleep: { slept.append($0) },
            look: { looks.removeFirst() },
            restore: { restored.append($0) }
        )

        #expect(restores == 1)
        #expect(restored == [["istat"]])
        #expect(slept == Array(repeating: LeftOutMemberWatch.pollInterval, count: 5))
        #expect(looks.count == 1, "No look after the member was placed")
    }

    @Test("A restore that was turned away is asked for again, a bounded number of times")
    func refusedRestoreIsRetried() async {
        var restored = 0

        let restores = await LeftOutMemberWatch.run(
            sleep: { _ in },
            look: { Self.arrived },
            restore: { _ in restored += 1 }
        )

        #expect(restores == LeftOutMemberWatch.maximumRestores)
        #expect(restored == LeftOutMemberWatch.maximumRestores)
    }

    @Test("A replaced watch ends without placing anything")
    func replacedWatchEnds() async {
        var restored = 0
        let result = await LeftOutMemberWatch.run(
            sleep: { _ in },
            look: { Situation(isCurrentWatch: false, liveLeftOutMembers: ["istat"]) },
            restore: { _ in restored += 1 }
        )

        #expect(result == 0)
        #expect(restored == 0)
    }

    @Test("The watch ends when the manager is gone or the wait is cancelled")
    func endsWithoutAManagerOrOnCancel() async {
        struct Cancelled: Error {}
        var restored = 0

        let gone = await LeftOutMemberWatch.run(sleep: { _ in }, look: { nil }, restore: { _ in restored += 1 })
        let cancelled = await LeftOutMemberWatch.run(sleep: { _ in throw Cancelled() }, look: { Self.arrived }, restore: { _ in restored += 1 })

        #expect(gone == 0)
        #expect(cancelled == 0)
        #expect(restored == 0)
    }

    /// 2026-11-11: CodexBar, a menu-bar-only app, started 12 s after a pass left it out. Its item
    /// moved no menu bar window, so the cache didn't see it for 30 s and the watch had nothing to restore.
    @Test("The watch re-reads the bar while a left-out member's app has just started")
    func readsTheBarAfterAnOwnerStarts() {
        #expect(LeftOutMemberWatch.step(Situation(ownerRecentlyLaunched: true)) == .readBar)
        #expect(LeftOutMemberWatch.step(Situation(liveLeftOutMembers: ["istat"], ownerRecentlyLaunched: true)) == .restore(["istat"]))
        #expect(LeftOutMemberWatch.step(Situation(hasLeftOutMembers: false, ownerRecentlyLaunched: true)) == .stop)
    }

    @Test("A started owner asks for a few re-reads, and an owner already running asks for none")
    func ownerLaunchesAskForBoundedReads() {
        var owners = LeftOutMemberWatch.OwnerLaunches(running: ["com.example.running"])

        let unchanged = owners.update(running: ["com.example.running"])
        let reads = (0 ..< 5).map { _ in owners.update(running: ["com.example.running", "com.example.late"]) }
        let another = owners.update(running: ["com.example.running", "com.example.late", "com.example.later"])

        #expect(!unchanged)
        #expect(reads == [true, true, true, false, false])
        #expect(LeftOutMemberWatch.readsAfterOwnerLaunch == 3)
        #expect(another, "Another start asks again")
    }

    /// iStat Menus was running when the pass gave up on it; its item showed up later with no launch to notice.
    @Test("A watch started while an owner already runs re-reads the bar for its first few looks")
    func readsAtStartForARunningOwner() {
        var owners = LeftOutMemberWatch.OwnerLaunches(running: ["com.example.slow"], readingAtStart: true)

        let reads = (0 ..< 4).map { _ in owners.update(running: ["com.example.slow"]) }

        #expect(reads == [true, true, true, false])
    }

    @Test("Only members named by a running app's bundle identifier have an owner to watch for")
    func runningOwnersNeedABundleIdentifier() {
        let members: Set = ["com.example.late:Item-0", "com.example.quit:Item-0", "Floe:Floe"]

        let owners = LeftOutMemberWatch.runningOwners(of: members, runningBundleIDs: ["com.example.late", "Floe"])

        #expect(owners == ["com.example.late"])
    }

    @Test("A re-read is followed by another look, and the arrival it finds is restored")
    func readBarThenRestore() async {
        var looks = [Situation(ownerRecentlyLaunched: true), Self.arrived, Situation(hasLeftOutMembers: false)]
        var reads = 0
        var restored = [Set<String>]()

        let restores = await LeftOutMemberWatch.run(
            sleep: { _ in },
            look: { looks.removeFirst() },
            readBar: { reads += 1 },
            restore: { restored.append($0) }
        )

        #expect(reads == 1)
        #expect(restores == 1)
        #expect(restored == [["istat"]])
        #expect(looks.isEmpty)
    }

    /// The restore's own pass can leave the member out again, which starts a new watch with no
    /// restores of its own; the cap holds across watches.
    @Test("A member restored the most times is no longer offered for restore, even to a new watch")
    func restoreCapOutlivesTheWatch() {
        let late = Self.item("Late", x: 10)
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [late]
        let start = ContinuousClock.now

        for generation in 1 ... LeftOutMemberWatch.maximumRestores {
            LeftOutMemberWatch.noteLeftOut([late.uniqueIdentifier], by: manager).cancel()
            let situation = LeftOutMemberWatch.situation(of: manager, generation: generation, startedAt: start)
            #expect(LeftOutMemberWatch.step(situation) == .restore([late.uniqueIdentifier]))
            manager.missingRepublishMemo.noteRestoreAsked(for: [late.uniqueIdentifier])
        }
        LeftOutMemberWatch.noteLeftOut([late.uniqueIdentifier], by: manager).cancel()
        let capped = LeftOutMemberWatch.situation(of: manager, generation: LeftOutMemberWatch.maximumRestores + 1, startedAt: start)

        #expect(capped.liveLeftOutMembers.isEmpty)
        #expect(LeftOutMemberWatch.step(capped) == .wait)
    }

    @Test("Leaving members out records them and replaces the running watch")
    func noteLeftOutStartsAWatch() {
        let manager = MenuBarItemManager()
        let start = ContinuousClock.now

        let first = LeftOutMemberWatch.noteLeftOut(["istat"], by: manager)
        let second = LeftOutMemberWatch.noteLeftOut(["vpn"], by: manager)
        first.cancel()
        second.cancel()

        #expect(manager.missingRepublishMemo.isKnownAbsent("istat"))
        #expect(manager.missingRepublishMemo.watchGeneration == 2)
        let situation = LeftOutMemberWatch.situation(of: manager, generation: 2, startedAt: start)
        #expect(situation.isCurrentWatch)
        #expect(situation.hasLeftOutMembers)
        #expect(situation.liveLeftOutMembers.isEmpty, "Nothing is on the bar in a bare manager")
        #expect(LeftOutMemberWatch.step(situation) == .wait)
        #expect(!LeftOutMemberWatch.situation(of: manager, generation: 1, startedAt: start).isCurrentWatch)
    }

    @Test("Only a left-out member in the Visible section counts, and a later ⌘-drag is noticed")
    func situationReadsTheVisibleSection() {
        let late = Self.item("Late", x: 10)
        let moved = Self.item("Moved", x: 40)
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [late]
        manager.itemCache[.hidden] = [moved]
        let start = ContinuousClock.now
        LeftOutMemberWatch.noteLeftOut([late.uniqueIdentifier, moved.uniqueIdentifier], by: manager).cancel()

        let situation = LeftOutMemberWatch.situation(of: manager, generation: 1, startedAt: start)
        #expect(situation.liveLeftOutMembers == [late.uniqueIdentifier])
        #expect(!situation.userDraggedSinceStart)

        manager.lastUserMenuBarDragEnd = .now
        #expect(LeftOutMemberWatch.situation(of: manager, generation: 1, startedAt: start).userDraggedSinceStart)
    }
}
