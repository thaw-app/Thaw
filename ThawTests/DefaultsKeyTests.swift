//
//  DefaultsKeyTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Pins the raw values of the hidden diagnostic flags that were migrated
/// from raw `UserDefaults` string-literal reads into `Defaults.Key`.
///
/// These raw values are a stored format: users may already have set them
/// via `defaults write`. If a raw value ever drifts from the historical
/// string literal, an existing user's setting is silently ignored with no
/// error. This test exists so a future rename of the enum case (which is
/// safe) cannot accidentally change the raw value (which is not) without
/// failing loudly.
///
/// Reads only; nothing here mutates the defaults domain, so the suite is
/// safe to run in parallel with the rest.
@Suite("Defaults keys")
struct DefaultsKeyTests {
    @Test("Hidden flag keys preserve their historical raw values")
    func hiddenFlagKeysPreserveTheirHistoricalRawValues() {
        #expect(Defaults.Key.inputPauseThresholdMs.rawValue == "inputPauseThresholdMs")
        #expect(Defaults.Key.discardStrayMoveEvents.rawValue == "discardStrayMoveEvents")
        #expect(Defaults.Key.failFastOnEventWindowMismatch.rawValue == "failFastOnEventWindowMismatch")
        #expect(Defaults.Key.axMessagingTimeout.rawValue == "axMessagingTimeout")
    }

    @Test("Hidden flag default values are unchanged")
    func hiddenFlagDefaultValuesAreUnchanged() {
        #expect(Defaults.DefaultValue.inputPauseThresholdMs == 50)
        #expect(Defaults.DefaultValue.discardStrayMoveEvents == true)
        #expect(Defaults.DefaultValue.failFastOnEventWindowMismatch == false)
        #expect(Defaults.DefaultValue.axMessagingTimeout == 1.0)
    }
}
