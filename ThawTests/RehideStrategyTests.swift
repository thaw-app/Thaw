//
//  RehideStrategyTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Rehide strategy")
struct RehideStrategyTests {
    // MARK: - Raw Value Tests

    @Test("smart has raw value 0")
    func smartRawValue() {
        #expect(RehideStrategy.smart.rawValue == 0)
    }

    @Test("timed has raw value 1")
    func timedRawValue() {
        #expect(RehideStrategy.timed.rawValue == 1)
    }

    @Test("focusedApp has raw value 2")
    func focusedAppRawValue() {
        #expect(RehideStrategy.focusedApp.rawValue == 2)
    }

    // MARK: - Init from Raw Value Tests

    @Test("Raw value 0 initializes smart")
    func initFromRawValueZero() {
        #expect(RehideStrategy(rawValue: 0) == .smart)
    }

    @Test("Raw value 1 initializes timed")
    func initFromRawValueOne() {
        #expect(RehideStrategy(rawValue: 1) == .timed)
    }

    @Test("Raw value 2 initializes focusedApp")
    func initFromRawValueTwo() {
        #expect(RehideStrategy(rawValue: 2) == .focusedApp)
    }

    @Test("An out-of-range raw value initializes nothing")
    func initFromInvalidRawValue() {
        #expect(RehideStrategy(rawValue: 3) == nil)
        #expect(RehideStrategy(rawValue: -1) == nil)
        #expect(RehideStrategy(rawValue: 100) == nil)
    }

    // MARK: - Identifiable Tests

    @Test("Every strategy's identifier is its raw value")
    func idMatchesRawValue() {
        for strategy in RehideStrategy.allCases {
            #expect(strategy.id == strategy.rawValue)
        }
    }

    // MARK: - CaseIterable Tests

    @Test("There are three strategies")
    func allCasesCount() {
        #expect(RehideStrategy.allCases.count == 3)
    }

    @Test("allCases lists every strategy")
    func allCasesContainsAllStrategies() {
        #expect(RehideStrategy.allCases.contains(.smart))
        #expect(RehideStrategy.allCases.contains(.timed))
        #expect(RehideStrategy.allCases.contains(.focusedApp))
    }

    // MARK: - fromString() Tests

    @Test("\"smart\" parses to smart")
    func fromStringSmart() {
        #expect(RehideStrategy.fromString("smart") == .smart)
    }

    @Test("\"timed\" parses to timed")
    func fromStringTimed() {
        #expect(RehideStrategy.fromString("timed") == .timed)
    }

    @Test("\"focusedApp\" parses to focusedApp")
    func fromStringFocusedApp() {
        #expect(RehideStrategy.fromString("focusedApp") == .focusedApp)
    }

    @Test("\"0\" parses to smart")
    func fromStringNumericZero() {
        #expect(RehideStrategy.fromString("0") == .smart)
    }

    @Test("\"1\" parses to timed")
    func fromStringNumericOne() {
        #expect(RehideStrategy.fromString("1") == .timed)
    }

    @Test("\"2\" parses to focusedApp")
    func fromStringNumericTwo() {
        #expect(RehideStrategy.fromString("2") == .focusedApp)
    }

    @Test("An unrecognized string parses to nothing")
    func fromStringInvalid() {
        #expect(RehideStrategy.fromString("invalid") == nil)
        #expect(RehideStrategy.fromString("3") == nil)
        #expect(RehideStrategy.fromString("") == nil)
        #expect(RehideStrategy.fromString("Smart") == nil) // case sensitive
        #expect(RehideStrategy.fromString("TIMED") == nil)
        #expect(RehideStrategy.fromString("focused_app") == nil) // snake_case not supported
    }
}
