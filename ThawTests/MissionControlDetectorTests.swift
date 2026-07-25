//
//  MissionControlDetectorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Covers `MissionControlDetector.nextInterval(isActive:lastStepUpSignal:now:)`,
/// the pure rate-selection function behind the detector's adaptive poll rate
/// (plan 009). The rest of the detector polls the window server for real
/// window displacement and isn't practically unit-testable; this is the one
/// piece of its logic that is.
@MainActor
final class MissionControlDetectorTests: XCTestCase {
    func testIdleWithNoSignalUsesIdleRate() {
        let now = Date()
        let interval = MissionControlDetector.nextInterval(
            isActive: false,
            lastStepUpSignal: nil,
            now: now
        )
        XCTAssertEqual(interval, MissionControlDetector.idleInterval)
    }

    func testIdleWithStaleSignalUsesIdleRate() {
        let now = Date()
        let staleSignal = now.addingTimeInterval(-(MissionControlDetector.activeSignalWindow + 1))
        let interval = MissionControlDetector.nextInterval(
            isActive: false,
            lastStepUpSignal: staleSignal,
            now: now
        )
        XCTAssertEqual(interval, MissionControlDetector.idleInterval)
    }

    func testRecentStepUpSignalUsesActiveRate() {
        let now = Date()
        let recentSignal = now.addingTimeInterval(-(MissionControlDetector.activeSignalWindow / 2))
        let interval = MissionControlDetector.nextInterval(
            isActive: false,
            lastStepUpSignal: recentSignal,
            now: now
        )
        XCTAssertEqual(interval, MissionControlDetector.activeInterval)
    }

    func testSignalExactlyAtWindowBoundaryUsesIdleRate() {
        let now = Date()
        let boundarySignal = now.addingTimeInterval(-MissionControlDetector.activeSignalWindow)
        let interval = MissionControlDetector.nextInterval(
            isActive: false,
            lastStepUpSignal: boundarySignal,
            now: now
        )
        XCTAssertEqual(interval, MissionControlDetector.idleInterval)
    }

    func testActiveAlwaysUsesActiveRateRegardlessOfSignal() {
        let now = Date()
        XCTAssertEqual(
            MissionControlDetector.nextInterval(isActive: true, lastStepUpSignal: nil, now: now),
            MissionControlDetector.activeInterval
        )

        let staleSignal = now.addingTimeInterval(-(MissionControlDetector.activeSignalWindow + 100))
        XCTAssertEqual(
            MissionControlDetector.nextInterval(isActive: true, lastStepUpSignal: staleSignal, now: now),
            MissionControlDetector.activeInterval
        )
    }
}
