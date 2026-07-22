//
//  NativeOverflowStateReducerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class NativeOverflowStateReducerTests: XCTestCase {
    func testDebouncesPresenceAndAbsenceAsymmetrically() {
        var reducer = NativeOverflowStateReducer(presentThreshold: 2, absentThreshold: 3)

        XCTAssertNil(reducer.consume(.present([]), on: 1))
        XCTAssertEqual(reducer.consume(.present([]), on: 1), true)
        XCTAssertTrue(reducer.isActive(on: 1))

        XCTAssertNil(reducer.consume(.absent, on: 1))
        XCTAssertNil(reducer.consume(.absent, on: 1))
        XCTAssertEqual(reducer.consume(.absent, on: 1), false)
        XCTAssertFalse(reducer.isActive(on: 1))
    }

    func testUnavailableObservationPreservesStableStateAndCandidate() {
        var reducer = NativeOverflowStateReducer(presentThreshold: 2, absentThreshold: 2)

        XCTAssertNil(reducer.consume(.present([]), on: 1))
        XCTAssertNil(reducer.consume(.unavailable, on: 1))
        XCTAssertEqual(reducer.consume(.present([]), on: 1), true)
        XCTAssertNil(reducer.consume(.unavailable, on: 1))
        XCTAssertTrue(reducer.isActive(on: 1))
    }

    func testTransientPresenceDoesNotPublish() {
        var reducer = NativeOverflowStateReducer(presentThreshold: 2, absentThreshold: 3)

        XCTAssertNil(reducer.consume(.present([]), on: 1))
        XCTAssertNil(reducer.consume(.absent, on: 1))
        XCTAssertFalse(reducer.isActive(on: 1))
    }

    func testDisplayStatesAreIndependent() {
        var reducer = NativeOverflowStateReducer(presentThreshold: 1, absentThreshold: 1)

        XCTAssertEqual(reducer.consume(.present([]), on: 1), true)
        XCTAssertTrue(reducer.isActive(on: 1))
        XCTAssertFalse(reducer.isActive(on: 2))
        XCTAssertEqual(reducer.consume(.present([]), on: 2), true)
        XCTAssertEqual(reducer.consume(.absent, on: 1), false)
        XCTAssertFalse(reducer.isActive(on: 1))
        XCTAssertTrue(reducer.isActive(on: 2))
    }

    /// Regression for the stale-display bug: a display that goes unobserved
    /// (no longer active/connected) must drop back to inactive and lose any
    /// in-progress debounce candidate, rather than resuming a stale count
    /// when it becomes active again.
    func testForgetClearsActiveStateAndDebounceCandidate() {
        var reducer = NativeOverflowStateReducer(presentThreshold: 2, absentThreshold: 2)

        XCTAssertNil(reducer.consume(.present([]), on: 1))
        XCTAssertEqual(reducer.consume(.present([]), on: 1), true)
        XCTAssertTrue(reducer.isActive(on: 1))
        // Start (but don't finish) a debounce toward absent.
        XCTAssertNil(reducer.consume(.absent, on: 1))

        reducer.forget(1)

        XCTAssertFalse(reducer.isActive(on: 1))
        // A single present observation after forgetting must not immediately
        // publish — the stale in-flight absent candidate must not leak into
        // the fresh state and skew the new debounce window.
        XCTAssertNil(reducer.consume(.present([]), on: 1))
        XCTAssertEqual(reducer.consume(.present([]), on: 1), true)
    }

    func testForgetIsNoOpForUntrackedDisplay() {
        var reducer = NativeOverflowStateReducer()

        reducer.forget(99)

        XCTAssertFalse(reducer.isActive(on: 99))
    }
}
