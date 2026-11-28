//
//  TerminatedItemCacheTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import PlatformRuntimeKit
import Testing
@testable import Thaw

@MainActor
struct TerminatedItemCacheTests {
    private func item(
        pid: pid_t,
        sourcePID explicitSourcePID: pid_t? = nil,
        bundle: String = "com.henrikruscon.Alcove",
        title: String = "Alcove"
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundle), title: title, instanceIndex: 0),
            windowID: 1,
            ownerPID: pid,
            sourcePID: explicitSourcePID ?? (pid > 0 ? pid : nil),
            bounds: CGRect(x: 100, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: false
        )
    }

    @Test("Rebucketing cannot resurrect a quit app from its concealed snapshot",
          arguments: [MenuBarSectionName.hidden, .alwaysHidden])
    func quitAppDoesNotReturn(section: MenuBarSectionName) {
        let snapshot = item(pid: 123)
        let assignments = [snapshot.uniqueIdentifier: section]
        let rebuilt = RuntimeCacheMapper.rebucket(
            MenuBarItemCache(displayID: 2),
            sectionFor: { _ in .visible },
            sectionAssignment: assignments,
            allowsAlwaysHidden: true,
            retainedSnapshotFor: { _ in snapshot },
            orderedItems: { items, _ in items }
        )
        // This is the real resurrection path, not just a stale input fixture.
        #expect(rebuilt[section] == [snapshot])
        let published = rebuilt.retainingRunningOwners(processIDs: [], bundleIdentifiers: [])
        #expect(published.managedItems.isEmpty)
        #expect(published.displayID == 2)
        #expect(assignments[snapshot.uniqueIdentifier] == section)
    }

    @Test("A still-running concealed owner survives absence from AX")
    func keepsRunningOwner() {
        let snapshot = item(pid: 123)
        var cache = MenuBarItemCache(displayID: nil)
        cache[.hidden] = [snapshot]
        #expect(cache.retainingRunningOwners(processIDs: [123], bundleIdentifiers: ["com.henrikruscon.Alcove"])[.hidden] == [snapshot])
    }

    @Test("A late scan cannot republish a departed owner in any section", arguments: MenuBarSectionName.allCases)
    func dropsLateScan(section: MenuBarSectionName) {
        var cache = MenuBarItemCache(displayID: nil)
        cache[section] = [item(pid: 123)]
        #expect(cache.retainingRunningOwners(processIDs: [], bundleIdentifiers: []).isEmpty)
    }

    @Test("Cold-start snapshots require a running publishing bundle")
    func coldStartSnapshot() {
        let snapshot = item(pid: 0)
        var cache = MenuBarItemCache(displayID: nil)
        cache[.hidden] = [snapshot]
        #expect(cache.retainingRunningOwners(processIDs: [456], bundleIdentifiers: ["com.henrikruscon.Alcove"])[.hidden] == [snapshot])
        #expect(cache.retainingRunningOwners(processIDs: [456], bundleIdentifiers: []).isEmpty)
    }

    @Test("A visible item of a relaunched app waits for the new process's item")
    func relaunchUsesNewVisibleItem() {
        var cache = MenuBarItemCache(displayID: nil)
        cache[.visible] = [item(pid: 123)]
        #expect(cache.retainingRunningOwners(processIDs: [456], bundleIdentifiers: ["com.henrikruscon.Alcove"]).isEmpty)
        cache[.visible] = [item(pid: 456)]
        #expect(cache.retainingRunningOwners(processIDs: [456], bundleIdentifiers: ["com.henrikruscon.Alcove"])[.visible].count == 1)
    }

    @Test("A hidden item seen before its app relaunched stays, without the old process",
          arguments: [MenuBarSectionName.hidden, .alwaysHidden])
    func relaunchKeepsHiddenItem(section: MenuBarSectionName) throws {
        let seen = item(pid: 123)
        var cache = MenuBarItemCache(displayID: nil)
        cache[section] = [seen]

        let kept = try #require(cache.retainingRunningOwners(
            processIDs: [456],
            bundleIdentifiers: ["com.henrikruscon.Alcove"]
        )[section].first)

        #expect(kept.uniqueIdentifier == seen.uniqueIdentifier)
        #expect(kept.bounds == seen.bounds)
        #expect(kept.ownerPID == 0)
        #expect(kept.sourcePID == nil)
        // The click path finds the relaunched process the way it does for a cold-start snapshot.
        #expect(ItemOwnerLookup.resolving(kept, runningPIDs: { _ in [456] }).sourcePID == 456)
    }

    @Test("A copy of an app that quit leaves its hidden item, while another copy with an item of its own still runs",
          arguments: [MenuBarSectionName.hidden, .alwaysHidden])
    func survivingCopyDoesNotKeepItem(section: MenuBarSectionName) {
        let survivor = item(pid: 456, title: "Alcove 2")
        var cache = MenuBarItemCache(displayID: nil)
        cache[section] = [item(pid: 123), survivor]

        let published = cache.retainingRunningOwners(processIDs: [456], bundleIdentifiers: ["com.henrikruscon.Alcove"])

        #expect(published[section] == [survivor])
    }

    @Test("Rebucketing brings back a hidden item of a relaunched app", arguments: [MenuBarSectionName.hidden, .alwaysHidden])
    func relaunchedAppReturns(section: MenuBarSectionName) {
        let snapshot = item(pid: 123)
        let rebuilt = RuntimeCacheMapper.rebucket(
            MenuBarItemCache(displayID: 2),
            sectionFor: { _ in .visible },
            sectionAssignment: [snapshot.uniqueIdentifier: section],
            allowsAlwaysHidden: true,
            retainedSnapshotFor: { _ in snapshot },
            orderedItems: { items, _ in items }
        )
        let published = rebuilt.retainingRunningOwners(processIDs: [456], bundleIdentifiers: ["com.henrikruscon.Alcove"])

        #expect(published[section].map(\.uniqueIdentifier) == [snapshot.uniqueIdentifier])
        // Without a PID the item no longer marks a departed owner for the liveness tick.
        #expect(published.livenessPIDs.isEmpty)
    }

    @Test("A cached item follows its source app rather than the hosting process")
    func livenessUsesSourcePID() {
        let cached = item(pid: 100, sourcePID: 200)
        var cache = MenuBarItemCache(displayID: nil)
        cache[.hidden] = [cached]

        // The app quit; only the hosting process still runs.
        #expect(cache.retainingRunningOwners(
            processIDs: [100],
            bundleIdentifiers: []
        ).isEmpty)
        #expect(cache.retainingRunningOwners(
            processIDs: [200],
            bundleIdentifiers: ["com.henrikruscon.Alcove"]
        )[.hidden] == [cached])
    }

    @Test("The tick's liveness sweep publishes a cache without the departed owner",
          arguments: MenuBarSectionName.allCases)
    func tickSweepDropsDepartedOwner(section: MenuBarSectionName) {
        let manager = MenuBarItemManager()
        var cache = MenuBarItemCache(displayID: 1)
        cache[section] = [item(pid: 111, bundle: "com.live.app"), item(pid: 222, bundle: "com.dead.app")]
        manager.itemCache = cache

        // The exit whose didTerminate notification never arrived: the owner's
        // PID and bundle are simply absent from the live table.
        manager.purgeDepartedOwners(processIDs: [111], bundleIdentifiers: ["com.live.app"])

        #expect(manager.managedItems(for: section).map(\.ownerPID) == [111])
    }

    @Test("An asynchronous liveness snapshot cannot prune a newer cache")
    func asynchronousSweepPreservesNewCache() async {
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [item(pid: 111)]

        await manager.purgeDepartedOwners(readOwners: {
            await MainActor.run {
                manager.itemCache[.visible] = [item(pid: 222)]
            }
            return RunningApplicationSnapshot(processIDs: [111], bundleIdentifiers: [])
        })

        #expect(manager.itemCache[.visible].map(\.ownerPID) == [222])
        #expect(!manager.isPurgingDepartedOwners)
    }

    @Test("Overlapping liveness ticks do not start another system query")
    func asynchronousSweepsDoNotOverlap() async {
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [item(pid: 111), item(pid: 222)]

        await manager.purgeDepartedOwners(readOwners: {
            await manager.purgeDepartedOwners(readOwners: {
                Issue.record("A previous liveness query is still in flight")
                return RunningApplicationSnapshot(processIDs: [], bundleIdentifiers: [])
            })
            return RunningApplicationSnapshot(processIDs: [111], bundleIdentifiers: [])
        })

        #expect(manager.itemCache[.visible].map(\.ownerPID) == [111])
        #expect(!manager.isPurgingDepartedOwners)
    }

    @Test("Cancellation after a liveness read leaves the published cache alone")
    func cancelledSweepDoesNotPublish() async {
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [item(pid: 111)]
        let sweep = Task {
            await manager.purgeDepartedOwners(readOwners: {
                withUnsafeCurrentTask { $0?.cancel() }
                return RunningApplicationSnapshot(processIDs: [], bundleIdentifiers: [])
            })
        }
        await sweep.value

        #expect(manager.itemCache[.visible].map(\.ownerPID) == [111])
        #expect(!manager.isPurgingDepartedOwners)
    }

    @Test("The tick's liveness sweep keeps a hidden item whose app relaunched")
    func tickSweepKeepsRelaunchedHiddenItem() {
        let manager = MenuBarItemManager()
        var cache = MenuBarItemCache(displayID: 1)
        cache[.hidden] = [item(pid: 222, bundle: "com.relaunched.app")]
        manager.itemCache = cache

        // The old process's didTerminate never arrived, and the app runs again as 333.
        manager.purgeDepartedOwners(processIDs: [333], bundleIdentifiers: ["com.relaunched.app"])

        #expect(manager.managedItems(for: .hidden).map(\.uniqueIdentifier) == cache[.hidden].map(\.uniqueIdentifier))
        #expect(manager.managedItems(for: .hidden).map(\.ownerPID) == [0])
    }

    @Test("The tick's liveness sweep leaves an all-owners-running cache untouched")
    func tickSweepKeepsRunningOwners() {
        let manager = MenuBarItemManager()
        var cache = MenuBarItemCache(displayID: 1)
        cache[.visible] = [item(pid: 111, bundle: "com.live.app")]
        cache[.hidden] = [item(pid: 0, bundle: "com.live.app")] // PID-less concealed snapshot
        manager.itemCache = cache

        manager.purgeDepartedOwners(processIDs: [111], bundleIdentifiers: ["com.live.app"])

        #expect(manager.managedItems(for: .visible).count == 1)
        #expect(manager.managedItems(for: .hidden).count == 1)
    }
}
