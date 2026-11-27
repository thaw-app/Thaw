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
}
