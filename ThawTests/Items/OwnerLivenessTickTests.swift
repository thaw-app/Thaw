//
//  OwnerLivenessTickTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
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

    /// One tick, reading a process table that holds the given processes and apps. Returns the
    /// tracked apps the tick found running again.
    @discardableResult
    private func tick(
        _ manager: MenuBarItemManager,
        probe: OwnerLivenessProbe,
        after seconds: Int,
        running: Set<pid_t>,
        apps bundles: Set<String> = []
    ) async -> Set<String> {
        await manager.purgeDepartedOwnersWhenDue(
            probe: probe,
            now: start.advanced(by: .seconds(seconds)),
            readOwners: { [reads] in
                reads.withLock { $0 += 1 }
                return RunningApplicationSnapshot(processIDs: running, bundleIdentifiers: bundles)
            }
        )
    }

    @Test("A tracked app that runs again is reported once, so its items are read without a launch notice")
    func trackedAppRunningAgainIsReported() async {
        let manager = MenuBarItemManager()
        manager.knownItemIdentifiers = ["com.example.app:Item"]
        // Each list stays alive to the end, so a later one cannot take an earlier one's identity.
        let withoutApp = NSObject()
        let withApp = NSObject()
        let later = NSObject()

        let quit = await tick(manager, probe: probe(apps: withoutApp), after: 0, running: [], apps: ["com.example.other"])
        let relaunched = await tick(manager, probe: probe(apps: withApp), after: 3, running: [], apps: ["com.example.other", "com.example.app"])
        let stillRunning = await tick(manager, probe: probe(apps: later), after: 6, running: [], apps: ["com.example.other", "com.example.app"])

        #expect(quit.isEmpty)
        #expect(relaunched == ["com.example.app"])
        #expect(stillRunning.isEmpty)
    }

    @Test("The first read reports no app, since every app is new to it")
    func firstReadReportsNothing() async {
        let manager = MenuBarItemManager()
        manager.knownItemIdentifiers = ["com.example.app:Item"]

        #expect(await tick(manager, probe: probe(apps: NSObject()), after: 0, running: [], apps: ["com.example.app"]).isEmpty)
    }

    @Test("An app with no tracked item is not reported when it starts")
    func untrackedAppIsNotReported() async {
        let manager = MenuBarItemManager()
        manager.knownItemIdentifiers = ["com.example.app:Item"]
        let before = NSObject()
        let after = NSObject()

        await tick(manager, probe: probe(apps: before), after: 0, running: [], apps: [])
        #expect(await tick(manager, probe: probe(apps: after), after: 3, running: [], apps: ["com.example.unrelated"]).isEmpty)
    }

    @Test("An app a launch notice already reported is not reported again")
    func launchNoticeIsNotRepeated() async {
        let manager = MenuBarItemManager()
        manager.knownItemIdentifiers = ["com.example.app:Item"]
        let before = NSObject()
        let after = NSObject()

        await tick(manager, probe: probe(apps: before), after: 0, running: [], apps: [])
        manager.ownerPurge.noteLaunched("com.example.app")
        #expect(await tick(manager, probe: probe(apps: after), after: 3, running: [], apps: ["com.example.app"]).isEmpty)
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
