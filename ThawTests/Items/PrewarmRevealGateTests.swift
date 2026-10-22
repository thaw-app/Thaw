//
//  PrewarmRevealGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("A prewarm reveals hidden items only when it can photograph them")
struct PrewarmRevealGateTests {
    @Test func revealsWithScreenRecordingAndAController() {
        #expect(ConcealedPrewarmGate.mayReveal(
            hasSectionController: true, screenRecordingGranted: true, nativeHidingActive: false
        ))
    }

    @Test func staysShutWithoutScreenRecording() {
        #expect(!ConcealedPrewarmGate.mayReveal(
            hasSectionController: true, screenRecordingGranted: false, nativeHidingActive: false
        ))
    }

    @Test func staysShutWithoutAController() {
        #expect(!ConcealedPrewarmGate.mayReveal(
            hasSectionController: false, screenRecordingGranted: true, nativeHidingActive: false
        ))
    }

    /// 2026-10-22 report: with native hiding each reveal switched an app back
    /// on, macOS rebuilt the bar, and every picture was refused anyway.
    @Test func staysShutWithNativeHiding() {
        #expect(!ConcealedPrewarmGate.mayReveal(
            hasSectionController: true, screenRecordingGranted: true, nativeHidingActive: true
        ))
    }

    @MainActor
    @Test func staysShutWithoutAnApp() {
        #expect(!ConcealedPrewarmGate.mayReveal(for: nil))
    }

    /// A prewarm the gate refuses returns without revealing or saving anything.
    @MainActor
    @Test func prewarmStopsAtTheGate() async {
        let appState = AppState()
        await appState.imageCache.prewarmConcealedImages(sections: [.hidden])
        #expect(appState.imageCache.capturesByTag.isEmpty)
    }
}
