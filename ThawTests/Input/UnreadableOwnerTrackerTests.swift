//
//  UnreadableOwnerTrackerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// An app drawn on the bar that the walk keeps missing is reported once, and
/// once more when it reads again.
@Suite("Unreadable owner tracker")
struct UnreadableOwnerTrackerTests {
    @Test("An owner the walk reads is never reported")
    func readableOwner() {
        var tracker = UnreadableOwnerTracker()
        for _ in 0 ..< 5 {
            #expect(tracker.note(drawn: [10], read: [10]) == .init())
        }
    }

    @Test("A drawn owner missed three reads in a row is reported once")
    func reportedAfterThreeMisses() {
        var tracker = UnreadableOwnerTracker()
        #expect(tracker.note(drawn: [10, 11], read: [10]).unreadable.isEmpty)
        #expect(tracker.note(drawn: [10, 11], read: [10]).unreadable.isEmpty)
        #expect(tracker.note(drawn: [10, 11], read: [10]).unreadable == [11])
        #expect(tracker.note(drawn: [10, 11], read: [10]).unreadable.isEmpty)
    }

    @Test("A miss while a reveal settles is forgotten once the owner is read")
    func settlingMissIsForgotten() {
        var tracker = UnreadableOwnerTracker()
        _ = tracker.note(drawn: [11], read: [])
        _ = tracker.note(drawn: [11], read: [])
        _ = tracker.note(drawn: [11], read: [11])
        #expect(tracker.note(drawn: [11], read: []).unreadable.isEmpty)
        #expect(tracker.reported.isEmpty)
    }

    @Test("A reported owner that reads again is announced once")
    func recoveryIsAnnounced() {
        var tracker = UnreadableOwnerTracker()
        for _ in 0 ..< 3 {
            _ = tracker.note(drawn: [11], read: [])
        }
        #expect(tracker.note(drawn: [11], read: [11]).readableAgain == [11])
        #expect(tracker.note(drawn: [11], read: [11]) == .init())
    }

    @Test("A reported owner that leaves the bar is dropped without a recovery line")
    func hiddenOwnerIsDropped() {
        var tracker = UnreadableOwnerTracker()
        for _ in 0 ..< 3 {
            _ = tracker.note(drawn: [11], read: [])
        }
        #expect(tracker.note(drawn: [], read: []) == .init())
        #expect(tracker.reported.isEmpty)
    }
}
