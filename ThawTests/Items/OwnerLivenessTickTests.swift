//
//  OwnerLivenessTickTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import os
import Testing
@testable import Thaw

@MainActor
struct OwnerLivenessTickTests {
    private let start = ContinuousClock.now
    private let reads = OSAllocatedUnfairLock(initialState: 0)

    private func item(pid: pid_t, sourcePID: pid_t? = nil, bundle: String = "com.example.app") -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundle), title: "Item", instanceIndex: 0),
            windowID: 1,
            ownerPID: pid,
            sourcePID: sourcePID,
            bounds: CGRect(x: 100, y: 0, width: 24, height: 24),
            title: "Item",
            isOnScreen: false
        )
    }

    /// A probe whose list of running apps is the given object and nothing else.
    private func probe(apps: AnyObject, dead: Set<pid_t> = []) -> OwnerLivenessProbe {
        let signature: Set<ObjectIdentifier> = [ObjectIdentifier(apps)]
        return OwnerLivenessProbe(isAlive: { !dead.contains($0) }, runningApplications: { signature })
    }

    /// One tick, reading a process table that holds the given processes.
    private func tick(
        _ manager: MenuBarItemManager,
        probe: OwnerLivenessProbe,
        after seconds: Int,
        running: Set<pid_t>
    ) async {
        await manager.purgeDepartedOwnersWhenDue(
            probe: probe,
            now: start.advanced(by: .seconds(seconds)),
            readOwners: { [reads] in
                reads.withLock { $0 += 1 }
                return RunningApplicationSnapshot(processIDs: running, bundleIdentifiers: [])
            }
        )
    }

    @Test("Ticks read the process table once while nothing has changed")
    func unchangedTicksReadOnce() async {
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [item(pid: 111)]
        let apps = NSObject()

        for seconds in [0, 3, 6] {
            await tick(manager, probe: probe(apps: apps), after: seconds, running: [111])
        }

        #expect(reads.withLock { $0 } == 1)
        #expect(manager.itemCache[.visible].map(\.ownerPID) == [111])
    }

    @Test("A cached owner whose process is gone is read and dropped on the next tick")
    func deadOwnerIsDropped() async {
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [item(pid: 111), item(pid: 222)]
        let apps = NSObject()

        await tick(manager, probe: probe(apps: apps), after: 0, running: [111, 222])
        await tick(manager, probe: probe(apps: apps, dead: [222]), after: 3, running: [111])

        #expect(reads.withLock { $0 } == 2)
        #expect(manager.itemCache[.visible].map(\.ownerPID) == [111])
    }

    @Test("A changed list of running apps is read on the next tick")
    func changedListIsRead() async {
        let manager = MenuBarItemManager()
        manager.itemCache[.hidden] = [item(pid: 0)]

        // Both lists stay alive to the end, so the second cannot take the first one's identity.
        let listedFirst = NSObject()
        let listed = NSObject()
        await tick(manager, probe: probe(apps: listedFirst), after: 0, running: [])
        let afterFirstRead = reads.withLock { $0 }
        await tick(manager, probe: probe(apps: listed), after: 3, running: [])
        await tick(manager, probe: probe(apps: listed), after: 6, running: [])

        #expect(afterFirstRead == 1)
        #expect(reads.withLock { $0 } == 2)
    }

    @Test("The backstop reads again although nothing cheaper changed")
    func backstopReadsAgain() async {
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [item(pid: 111)]
        let apps = NSObject()
        let backstop = Int(OwnerLivenessGate<Set<ObjectIdentifier>>.backstop.components.seconds)

        await tick(manager, probe: probe(apps: apps), after: 0, running: [111])
        await tick(manager, probe: probe(apps: apps), after: backstop - 1, running: [111])
        await tick(manager, probe: probe(apps: apps), after: backstop, running: [111])

        #expect(reads.withLock { $0 } == 2)
    }

    @Test("A tick does not start a read while one is in flight")
    func ticksDoNotOverlap() async {
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [item(pid: 111)]
        let apps = NSObject()
        let inner = probe(apps: apps, dead: [111])

        await manager.purgeDepartedOwnersWhenDue(probe: probe(apps: apps), now: start, readOwners: {
            await manager.purgeDepartedOwnersWhenDue(probe: inner, readOwners: {
                Issue.record("A previous liveness read is still in flight")
                return RunningApplicationSnapshot(processIDs: [], bundleIdentifiers: [])
            })
            return RunningApplicationSnapshot(processIDs: [111], bundleIdentifiers: [])
        })

        #expect(manager.itemCache[.visible].map(\.ownerPID) == [111])
        #expect(!manager.isPurgingDepartedOwners)
    }

    @Test("Liveness PIDs are each item's source process, else its owner, and skip items without one")
    func livenessPIDs() {
        var cache = MenuBarItemCache(displayID: nil)
        cache[.visible] = [item(pid: 111), item(pid: 222, sourcePID: 333)]
        cache[.hidden] = [item(pid: 0)]
        cache[.alwaysHidden] = [item(pid: 444)]

        #expect(cache.livenessPIDs == [111, 333, 444])
    }

    @Test("The live probe finds this process and not an ID no process has")
    func liveProbe() {
        #expect(OwnerLivenessProbe.live.isAlive(getpid()))
        #expect(!OwnerLivenessProbe.live.isAlive(pid_t.max))
        #expect(!OwnerLivenessProbe.live.runningApplications().isEmpty)
    }
}
