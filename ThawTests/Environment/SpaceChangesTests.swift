//
//  SpaceChangesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

@Suite("Space change coalescing")
struct SpaceChangeCoalescerTests {
    private let start = ContinuousClock.now

    @Test("The two window server events and the notification after them make one switch")
    func oneSwitch() {
        var coalescer = SpaceChangeCoalescer()
        #expect(coalescer.admit(.activeSpace, activeSpaceID: 7, at: start) == .activeSpace(7))
        #expect(coalescer.admit(.activeSpace, activeSpaceID: 7, at: start + .milliseconds(5)) == nil)
        #expect(coalescer.admit(.activeSpace, activeSpaceID: 7, at: start + .milliseconds(300)) == nil)
    }

    @Test("A switch to another Space is delivered at once")
    func quickSwitches() {
        var coalescer = SpaceChangeCoalescer()
        _ = coalescer.admit(.activeSpace, activeSpaceID: 7, at: start)
        #expect(coalescer.admit(.activeSpace, activeSpaceID: 8, at: start + .milliseconds(50)) == .activeSpace(8))
        #expect(coalescer.admit(.activeSpace, activeSpaceID: 7, at: start + .milliseconds(100)) == .activeSpace(7))
    }

    @Test("The same Space after the window counts again")
    func afterWindow() {
        var coalescer = SpaceChangeCoalescer()
        _ = coalescer.admit(.activeSpace, activeSpaceID: 7, at: start)
        #expect(coalescer.admit(.activeSpace, activeSpaceID: 7, at: start + SpaceChangeCoalescer.duplicateWindow) == .activeSpace(7))
    }

    @Test("Every Space list event passes, and does not hide a switch")
    func spaceList() {
        var coalescer = SpaceChangeCoalescer()
        #expect(coalescer.admit(.spaceList, activeSpaceID: 7, at: start) == .spaceList)
        #expect(coalescer.admit(.spaceList, activeSpaceID: 7, at: start + .milliseconds(20)) == .spaceList)
        #expect(coalescer.admit(.activeSpace, activeSpaceID: 7, at: start + .milliseconds(30)) == .activeSpace(7))
    }
}

@MainActor
@Suite("Space change source")
struct SpaceChangesTests {
    @Test("Subscribers get each change once, in order")
    func deliversOnce() async {
        let clock = TestClock()
        var spaceID: CGSSpaceID = 3
        let source = SpaceChanges(activeSpaceID: { spaceID }, now: { clock.now })
        let (feed, input) = AsyncStream<SpaceSignal>.makeStream()
        source.start(feed: feed)
        var first = source.changes().makeAsyncIterator()
        var second = source.changes().makeAsyncIterator()

        input.yield(.activeSpace)
        input.yield(.activeSpace)
        input.yield(.activeSpace)
        #expect(await first.next() == .activeSpace(3))
        spaceID = 4
        input.yield(.activeSpace)
        input.yield(.spaceList)
        #expect(await first.next() == .activeSpace(4))
        #expect(await first.next() == .spaceList)
        #expect(await second.next() == .activeSpace(3))
        #expect(await second.next() == .activeSpace(4))
        #expect(await second.next() == .spaceList)
        source.stop()
    }

    @Test("A debounced task runs once for a burst, with the last Space")
    func debouncedTask() async {
        var spaceID: CGSSpaceID = 1
        let source = SpaceChanges(activeSpaceID: { spaceID })
        let (seen, seenInput) = AsyncStream<CGSSpaceID>.makeStream()
        let task = source.activeSpaceTask(debounce: .milliseconds(50)) { seenInput.yield($0) }
        await Task.yield()
        source.admit(.activeSpace)
        spaceID = 2
        source.admit(.activeSpace)
        var iterator = seen.makeAsyncIterator()
        #expect(await iterator.next() == 2)
        task.cancel()
    }

    @Test("An undebounced task runs for every switch")
    func plainTask() async {
        var spaceID: CGSSpaceID = 1
        let source = SpaceChanges(activeSpaceID: { spaceID })
        let (seen, seenInput) = AsyncStream<CGSSpaceID>.makeStream()
        let task = source.activeSpaceTask { seenInput.yield($0) }
        source.admit(.activeSpace)
        spaceID = 2
        source.admit(.activeSpace)
        var iterator = seen.makeAsyncIterator()
        #expect(await iterator.next() == 1)
        #expect(await iterator.next() == 2)
        task.cancel()
    }

    @Test("The live feed turns the NSWorkspace notification into a signal")
    func liveFeedNotification() async {
        let center = NotificationCenter()
        let feed = SpaceChanges.liveFeed(center: center)
        center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        var iterator = feed.makeAsyncIterator()
        #expect(await iterator.next() == .activeSpace)
    }
}

@MainActor
@Suite("Space directory")
struct SpaceDirectoryTests {
    private static func space(_ id: CGSSpaceID, _ key: String) -> Bridging.ManagedSpace {
        Bridging.ManagedSpace(spaceID: id, persistentKey: key, displayIdentifier: "D", ordinal: Int(id))
    }

    @Test("A Space list change re-reads the list; a missing key answers nil")
    func refreshesOnListChange() async {
        var listed = [Self.space(1, "a")]
        let directory = SpaceDirectory(read: { listed })
        let source = SpaceChanges(activeSpaceID: { 1 })
        directory.start(changes: source, debounce: .milliseconds(1))
        #expect(directory.space(forKey: "a")?.spaceID == 1)

        listed = [Self.space(2, "b")]
        let changed = Task { @MainActor in
            for await _ in Observations({ directory.spaces }).dropFirst() {
                return
            }
        }
        await Task.yield()
        source.admit(.spaceList)
        await changed.value
        #expect(directory.space(forKey: "a") == nil)
        #expect(directory.space(forKey: "b")?.spaceID == 2)
        directory.stop()
    }

    @Test("Refreshing an unchanged list keeps the same value")
    func unchangedList() {
        let directory = SpaceDirectory(read: { [Self.space(1, "a")] })
        directory.refresh()
        #expect(directory.spaces.map(\.persistentKey) == ["a"])
    }
}
