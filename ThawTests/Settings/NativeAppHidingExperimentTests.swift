//
//  NativeAppHidingExperimentTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// An experiment that was never started touches no app list, so its state is what Settings shows first.
@MainActor
@Suite("Native app hiding experiment")
struct NativeAppHidingExperimentTests {
    @Test("Before any start, native hiding is off and reports no failure, no recovery problem and no unreadable record")
    func unstartedExperimentIsQuiet() {
        let experiment = NativeAppHidingExperiment()
        #expect(!experiment.isActive)
        #expect(experiment.lastError == nil)
        #expect(!experiment.previousSessionRecoveryFailed)
        #expect(!experiment.journalNeedsAttention)
        #expect(experiment.failedStartNotice == nil)
    }
}
