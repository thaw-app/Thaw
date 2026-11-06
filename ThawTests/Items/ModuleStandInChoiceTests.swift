//
//  ModuleStandInChoiceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Module stand-in choice")
@MainActor
struct ModuleStandInChoiceTests {
    @Test("A stand-in runs when stand-ins are on and its checkbox is left on")
    func chosen() {
        #expect(SystemExtraTakeoverCoordinator.isChosen(.airDrop, enabled: true, skipped: []))
        #expect(SystemExtraTakeoverCoordinator.isChosen(.airDrop, enabled: true, skipped: ["focus"]))
    }

    @Test("Unchecking an item, or turning stand-ins off, keeps Apple's own")
    func notChosen() {
        #expect(!SystemExtraTakeoverCoordinator.isChosen(.airDrop, enabled: true, skipped: ["airdrop"]))
        #expect(!SystemExtraTakeoverCoordinator.isChosen(.focus, enabled: false, skipped: []))
    }
}
