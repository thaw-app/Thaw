//
//  NotchRevealWaitTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The notch panel waits for its body to grow or retract only while it animates.
@MainActor
@Suite("Notch reveal wait")
struct NotchRevealWaitTests {
    @Test("The wait matches the spring, and Reduce Motion, which cuts the spring, skips it")
    func waitFollowsReduceMotion() {
        #expect(NotchMetrics.revealWait(reduceMotion: false) == NotchMetrics.revealDuration)
        #expect(NotchMetrics.revealWait(reduceMotion: true) == .zero)
        _ = NotchMetrics.revealWait()
    }
}
