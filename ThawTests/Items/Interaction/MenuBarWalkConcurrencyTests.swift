//
//  MenuBarWalkConcurrencyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Synchronization
import Testing
@testable import Thaw
import ThawAXCore

/// Records which apps the walk read and how many it read at once.
private final class ReadLog: Sendable {
    private struct State {
        var read: [pid_t] = []
        var current = 0
        var peak = 0
    }

    private let state = Mutex(State())

    var read: [pid_t] {
        state.withLock { $0.read }
    }

    var peak: Int {
        state.withLock { $0.peak }
    }

    func enter(_ pid: pid_t) {
        state.withLock {
            $0.read.append(pid)
            $0.current += 1
            $0.peak = max($0.peak, $0.current)
        }
    }

    func leave() {
        state.withLock { $0.current -= 1 }
    }
}

/// The walk over the test host's running apps, with a reader that stands in for Accessibility.
@Suite("Menu bar walk concurrency", .serialized)
struct MenuBarWalkConcurrencyTests {
    private typealias Provider = MenuBarItemAXProvider

    private static var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
    }

    /// Every running app but the test host, whose own read waits on the main actor the rest of the suite keeps busy.
    private static var otherApps: [NSRunningApplication] {
        runningApps.filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }

    /// Apps other than the test host that can show items, to give the fake reader something to answer.
    private static var itemOwners: [NSRunningApplication] {
        runningApps.filter {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.activationPolicy != .prohibited
        }
    }

    private static var itemOwner: NSRunningApplication? {
        itemOwners.first
    }

    /// A different app from itemOwner, so the cooldown a slow read leaves can't reach the other tests.
    private static var slowOwner: NSRunningApplication? {
        itemOwners.dropFirst().first
    }

    private static func item(for pid: pid_t) -> Provider.RawItem {
        Provider.RawItem(
            namespace: .string("com.example.walk"),
            identityTitle: "Walk",
            displayTitle: "Walk",
            bounds: CGRect(x: 1200, y: 4, width: 24, height: 22),
            ownerPID: pid
        )
    }

    @Test(
        "Several apps are read at once, never more than the limit, and every app is read once",
        .enabled(if: MenuBarWalkConcurrencyTests.itemOwner != nil, "needs an app besides the test host")
    )
    func readsAppsInParallel() async throws {
        let owner = try #require(Self.itemOwner).processIdentifier
        let log = ReadLog()
        let reader = Provider.WalkReader(runningApps: { Self.otherApps }, isTrusted: { true }, read: { app, _, _, _ in
            log.enter(app.processIdentifier)
            Thread.sleep(forTimeInterval: 0.005)
            log.leave()
            return app.processIdentifier == owner ? [Self.item(for: owner)] : []
        })

        let (snapshot, _) = await Provider.enumerateMenuBarItemsResilient(
            state: MenuBarScanState(),
            scope: .discovery,
            priorityPIDs: [],
            reader: reader
        )

        #expect(log.peak <= Provider.walkConcurrency)
        #expect(log.peak > 1)
        #expect(Set(log.read).count == log.read.count)
        #expect(snapshot.items.contains { $0.ownerPID == owner })
    }

    @Test("Background-only apps are read after every app that can show items")
    func backgroundOnlyAppsGoLast() {
        let apps = Self.runningApps
        let background = Provider.backgroundOnlyPIDs(among: apps)
        #expect(background == Set(apps.filter { $0.activationPolicy == .prohibited }.map(\.processIdentifier)))
        var state = MenuBarScanState<Provider.RawItem>()
        let pass = state.begin(owners: apps.map(\.processIdentifier), priorityOwners: [], deferredOwners: background)
        let firstBackground = pass.owners.firstIndex { background.contains($0) } ?? pass.owners.count
        #expect(pass.owners[firstBackground...].allSatisfy { background.contains($0) })
    }

    @Test(
        "An app that misses its deadline is skipped and the walk reports itself incomplete",
        .enabled(if: MenuBarWalkConcurrencyTests.slowOwner != nil, "needs two apps besides the test host")
    )
    func slowAppTruncatesTheWalk() async throws {
        let slow = try #require(Self.slowOwner).processIdentifier
        let reader = Provider.WalkReader(runningApps: { Self.otherApps }, isTrusted: { true }, read: { app, _, _, _ in
            if app.processIdentifier == slow {
                Thread.sleep(forTimeInterval: 0.6)
            }
            return []
        })

        let (snapshot, _) = await Provider.enumerateMenuBarItemsResilient(
            state: MenuBarScanState(),
            scope: .discovery,
            priorityPIDs: [],
            reader: reader
        )

        #expect(!snapshot.completed)
    }

    @Test("Without Accessibility the walk reads nothing")
    func untrustedWalkReadsNothing() async {
        let log = ReadLog()
        let reader = Provider.WalkReader(isTrusted: { false }, read: { app, _, _, _ in
            log.enter(app.processIdentifier)
            return []
        })

        let (snapshot, _) = await Provider.enumerateMenuBarItemsResilient(
            state: MenuBarScanState(),
            scope: .discovery,
            priorityPIDs: [],
            reader: reader
        )

        #expect(log.read.isEmpty)
        #expect(!snapshot.completed)
    }

    @Test("The walk reads with a shorter timeout than presses and moves, and an element with no children gives none")
    func walkTimeoutIsShort() {
        #expect(Provider.walkMessagingTimeout <= 0.25)
        let unanswered = AXElement.application(-1)
        #expect(Provider.walkChildren(of: unanswered).isEmpty)
    }
}
