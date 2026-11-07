//
//  BentoEntranceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The onboarding tiles' staggered entrance.
@MainActor
@Suite("Bento entrance")
struct BentoEntranceTests {
    @Test("No gap is longer than the one before, and the whole entrance stays brief")
    func staggerTapers() {
        let delays = (0 ..< 8).map(BentoTile.entranceDelay(index:))
        let gaps = zip(delays.dropFirst(), delays).map { $0 - $1 }
        #expect(delays.first == 0)
        #expect(zip(gaps.dropFirst(), gaps).allSatisfy { $0 <= $1 + 1e-9 })
        #expect(delays.last == 0.12)
        #expect(BentoTile.entranceDelay(index: 20) == 0.12)
        #expect(BentoTile.entranceDelay(index: -1) == 0)
    }
}
