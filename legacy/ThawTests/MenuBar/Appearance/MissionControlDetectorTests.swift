//
//  MissionControlDetectorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers `MissionControlDetector.nextInterval(isActive:lastStepUpSignal:now:)`,
/// the pure rate selection behind the detector's adaptive poll rate. The rest
/// polls the window server.
@MainActor
@Suite("Mission control detector")
struct MissionControlDetectorTests {
    @Test("Idle with no signal uses the idle rate")
    func idleWithNoSignalUsesIdleRate() {
        let now = Date()
        let interval = MissionControlDetector.nextInterval(
            isActive: false,
            lastStepUpSignal: nil,
            now: now
        )
        #expect(interval == MissionControlDetector.idleInterval)
    }

    @Test("Idle with a stale signal uses the idle rate")
    func idleWithStaleSignalUsesIdleRate() {
        let now = Date()
        let staleSignal = now.addingTimeInterval(-(MissionControlDetector.activeSignalWindow + 1))
        let interval = MissionControlDetector.nextInterval(
            isActive: false,
            lastStepUpSignal: staleSignal,
            now: now
        )
        #expect(interval == MissionControlDetector.idleInterval)
    }

    @Test("A recent step-up signal uses the active rate")
    func recentStepUpSignalUsesActiveRate() {
        let now = Date()
        let recentSignal = now.addingTimeInterval(-(MissionControlDetector.activeSignalWindow / 2))
        let interval = MissionControlDetector.nextInterval(
            isActive: false,
            lastStepUpSignal: recentSignal,
            now: now
        )
        #expect(interval == MissionControlDetector.activeInterval)
    }

    @Test("A signal exactly at the window boundary uses the idle rate")
    func signalExactlyAtWindowBoundaryUsesIdleRate() {
        let now = Date()
        let boundarySignal = now.addingTimeInterval(-MissionControlDetector.activeSignalWindow)
        let interval = MissionControlDetector.nextInterval(
            isActive: false,
            lastStepUpSignal: boundarySignal,
            now: now
        )
        #expect(interval == MissionControlDetector.idleInterval)
    }

    @Test("Active always uses the active rate regardless of the signal")
    func activeAlwaysUsesActiveRateRegardlessOfSignal() {
        let now = Date()
        #expect(
            MissionControlDetector.nextInterval(isActive: true, lastStepUpSignal: nil, now: now)
                == MissionControlDetector.activeInterval
        )

        let staleSignal = now.addingTimeInterval(-(MissionControlDetector.activeSignalWindow + 100))
        #expect(
            MissionControlDetector.nextInterval(isActive: true, lastStepUpSignal: staleSignal, now: now)
                == MissionControlDetector.activeInterval
        )
    }
}
