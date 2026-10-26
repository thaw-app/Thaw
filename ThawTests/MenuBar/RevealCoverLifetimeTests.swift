//
//  RevealCoverLifetimeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Reveal cover lifetime")
struct RevealCoverLifetimeTests {
    @Test("A capture's cover outlives a batch whose last settle poll starts at the budget and reads a crowded bar")
    func captureCoverOutlivesBatch() {
        // One whole-bar read took up to 7 s with about 135 apps running.
        let slowestRead = Duration.seconds(7)
        let batch = Constants.MenuBarTuning.revealCaptureSettleBudget
            + slowestRead
            + Constants.MenuBarTuning.layoutPrewarmRenderSettle
        #expect(Constants.MenuBarTuning.revealCaptureCoverLifetime > batch)
    }
}
