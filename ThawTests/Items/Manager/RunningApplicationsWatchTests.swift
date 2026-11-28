//
//  RunningApplicationsWatchTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

struct RunningApplicationsWatchTests {
    @Test("New processes count as launched and missing ones as quit, each once")
    func difference() {
        let change = RunningApplicationsWatch.difference(from: [1, 2, 3], to: [2, 3, 4, 5])
        #expect(change.launched == [4, 5])
        #expect(change.terminated == [1])
        let none = RunningApplicationsWatch.difference(from: [1, 2], to: [1, 2])
        #expect(none.launched.isEmpty && none.terminated.isEmpty)
    }

    @Test("A copy started beside a running app is not a launch; a relaunch and a new app are")
    func secondCopies() {
        let copies = RunningApplicationsWatch.secondCopies(
            launched: [10: "com.example.sync", 11: "com.example.new", 12: "com.example.relaunched"],
            alreadyRunning: ["com.example.sync", "com.example.other"]
        )
        #expect(copies == [10])
    }
}
