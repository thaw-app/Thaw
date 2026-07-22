//
//  RehideStrategyTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class RehideStrategyTests: XCTestCase {
    func testCasesAndRawValuesRemainStable() {
        let expected: [(RehideStrategy, Int)] = [(.smart, 0), (.timed, 1), (.focusedApp, 2)]

        XCTAssertEqual(RehideStrategy.allCases, expected.map(\.0))
        for (strategy, rawValue) in expected {
            XCTAssertEqual(strategy.rawValue, rawValue)
            XCTAssertEqual(RehideStrategy(rawValue: rawValue), strategy)
        }
        XCTAssertNil(RehideStrategy(rawValue: 3))
        XCTAssertNil(RehideStrategy(rawValue: -1))
        XCTAssertNil(RehideStrategy(rawValue: 100))
    }

    func testStringParsing() {
        let valid: [(String, RehideStrategy)] = [
            ("smart", .smart), ("0", .smart),
            ("timed", .timed), ("1", .timed),
            ("focusedApp", .focusedApp), ("2", .focusedApp),
        ]
        for (value, expected) in valid {
            XCTAssertEqual(RehideStrategy.fromString(value), expected)
        }
        for invalid in ["invalid", "3", "", "Smart", "TIMED", "focused_app"] {
            XCTAssertNil(RehideStrategy.fromString(invalid))
        }
    }
}
