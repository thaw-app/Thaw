//
//  DefaultsKeyTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Pins the raw values of the hidden diagnostic flags that were migrated
/// from raw `UserDefaults` string-literal reads into `Defaults.Key`.
///
/// These raw values are a stored format: users may already have set them
/// via `defaults write`. If a raw value ever drifts from the historical
/// string literal, an existing user's setting is silently ignored with no
/// error. This test exists so a future rename of the enum case (which is
/// safe) cannot accidentally change the raw value (which is not) without
/// failing loudly.
final class DefaultsKeyTests: XCTestCase {
    func testHiddenFlagKeysPreserveTheirHistoricalRawValues() {
        XCTAssertEqual(Defaults.Key.inputPauseThresholdMs.rawValue, "inputPauseThresholdMs")
        XCTAssertEqual(Defaults.Key.discardStrayMoveEvents.rawValue, "discardStrayMoveEvents")
        XCTAssertEqual(Defaults.Key.failFastOnEventWindowMismatch.rawValue, "failFastOnEventWindowMismatch")
        XCTAssertEqual(Defaults.Key.axMessagingTimeout.rawValue, "axMessagingTimeout")
    }

    func testHiddenFlagDefaultValuesAreUnchanged() {
        XCTAssertEqual(Defaults.DefaultValue.inputPauseThresholdMs, 50)
        XCTAssertEqual(Defaults.DefaultValue.discardStrayMoveEvents, true)
        XCTAssertEqual(Defaults.DefaultValue.failFastOnEventWindowMismatch, false)
        XCTAssertEqual(Defaults.DefaultValue.axMessagingTimeout, 1.0)
    }
}
