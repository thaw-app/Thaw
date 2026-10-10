//
//  CacheGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Cache gate")
struct CacheGateTests {
    @Test("Admits one pass at a time and coalesces reruns into one follow-up")
    func admissionAndCoalescedReruns() async {
        let gate = MenuBarItemManager.CacheGate()

        #expect(await gate.begin(), "The first pass must be admitted")
        #expect(await gate.begin() == false, "A concurrent pass must be rejected")
        #expect(await gate.begin() == false, "Further concurrent passes must still be rejected")
        #expect(await gate.end(), "A rerun must be requested after concurrent rejections")

        #expect(await gate.begin(), "The follow-up pass must be admitted")
        #expect(await gate.end() == false, "A quiet pass must not report a rerun")
    }
}
