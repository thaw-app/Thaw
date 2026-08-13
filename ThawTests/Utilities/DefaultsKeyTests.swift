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
        #expect(Defaults.Key.bulkApplyIdleThresholdMs.rawValue == "bulkApplyIdleThresholdMs")
        #expect(Defaults.Key.bulkApplyIdleWaitCapMs.rawValue == "bulkApplyIdleWaitCapMs")
        #expect(Defaults.Key.enforceConcealedSectionOrder.rawValue == "enforceConcealedSectionOrder")
        #expect(Defaults.Key.automaticArrangementEnabled.rawValue == "automaticArrangementEnabled")
        #expect(Defaults.Key.postMoveEventsToWindowOwner.rawValue == "postMoveEventsToWindowOwner")
        #expect(Defaults.Key.discardStrayMoveEvents.rawValue == "discardStrayMoveEvents")
        #expect(Defaults.Key.failFastOnEventWindowMismatch.rawValue == "failFastOnEventWindowMismatch")
        #expect(Defaults.Key.axMessagingTimeout.rawValue == "axMessagingTimeout")
    }

    @Test("Hidden flag default values are unchanged")
    func hiddenFlagDefaultValuesAreUnchanged() {
        #expect(Defaults.DefaultValue.inputPauseThresholdMs == 50)
        // 0 keeps the bulk idle gate off: enabling it by default would
        // change when every automatic apply starts.
        #expect(Defaults.DefaultValue.bulkApplyIdleThresholdMs == 0)
        #expect(Defaults.DefaultValue.bulkApplyIdleWaitCapMs == 2000)
        // True: order within concealed sections is what the saved layout
        // describes, and dropping it would change what restore means.
        #expect(Defaults.DefaultValue.enforceConcealedSectionOrder == true)
        // True keeps Thaw arranging on its own initiative; false is the
        // manual-only escape hatch.
        #expect(Defaults.DefaultValue.automaticArrangementEnabled == true)
        // False: routing events to the window's owner changes where every
        // synthetic event goes, so it stays opt-in.
        #expect(Defaults.DefaultValue.postMoveEventsToWindowOwner == false)
        #expect(Defaults.DefaultValue.discardStrayMoveEvents == true)
        #expect(Defaults.DefaultValue.failFastOnEventWindowMismatch == false)
        #expect(Defaults.DefaultValue.axMessagingTimeout == 1.0)
    }
}
