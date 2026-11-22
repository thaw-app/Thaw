//
//  PrewarmRevealGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Hidden items are revealed for a picture only when one can be taken", .scratchDefaults)
struct PrewarmRevealGateTests {
    @Test func revealsWithScreenRecordingAndAController() {
        #expect(ConcealedPrewarmGate.mayReveal(hasSectionController: true, screenRecordingGranted: true))
    }

    @Test func staysShutWithoutScreenRecording() {
        #expect(!ConcealedPrewarmGate.mayReveal(hasSectionController: true, screenRecordingGranted: false))
    }

    @Test func staysShutWithoutAController() {
        #expect(!ConcealedPrewarmGate.mayReveal(hasSectionController: false, screenRecordingGranted: true))
    }

    @MainActor
    @Test func staysShutWithoutAnApp() {
        #expect(!ConcealedPrewarmGate.mayReveal(for: nil))
    }

    /// Capture Hidden Items, refused by the gate, returns without revealing or saving anything.
    @MainActor
    @Test func captureStopsAtTheGate() async {
        let appState = AppState()
        let result = await appState.imageCache.captureHiddenItems()
        #expect(result == nil)
        #expect(appState.imageCache.capturesByTag.isEmpty)
    }
}
