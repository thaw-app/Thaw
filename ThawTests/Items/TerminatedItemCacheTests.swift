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
    private func item(pid: pid_t, bundle: String = "com.henrikruscon.Alcove") -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundle), title: "Alcove", instanceIndex: 0),
            windowID: 1,
            ownerPID: pid,
            sourcePID: pid > 0 ? pid : nil,
            bounds: CGRect(x: 100, y: 0, width: 24, height: 24),
            title: "Alcove",
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

    @Test("Relaunch does not validate a snapshot belonging to the old process")
    func relaunchUsesNewSnapshot() {
        var cache = MenuBarItemCache(displayID: nil)
        cache[.hidden] = [item(pid: 123)]
        #expect(cache.retainingRunningOwners(processIDs: [456], bundleIdentifiers: ["com.henrikruscon.Alcove"]).isEmpty)
        cache[.hidden] = [item(pid: 456)]
        #expect(cache.retainingRunningOwners(processIDs: [456], bundleIdentifiers: ["com.henrikruscon.Alcove"])[.hidden].count == 1)
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
