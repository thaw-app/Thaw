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
        // 300 arms the bulk idle gate: a batch dispatched mid-interaction
        // contests the pointer for its whole length.
        #expect(Defaults.DefaultValue.bulkApplyIdleThresholdMs == 300)
        #expect(Defaults.DefaultValue.bulkApplyIdleWaitCapMs == 2000)
        // False: ordering moves inside concealed sections are invisible and
        // dominate long batches, so membership alone is restored.
        #expect(Defaults.DefaultValue.enforceConcealedSectionOrder == false)
        // True keeps Thaw arranging on its own initiative; false is the
        // manual-only escape hatch.
        #expect(Defaults.DefaultValue.automaticArrangementEnabled == true)
        // True: on macOS 26 the window's owner is the process that receives
        // the drag, and it is what lets an unresolved slot move at all.
        #expect(Defaults.DefaultValue.postMoveEventsToWindowOwner == true)
        #expect(Defaults.DefaultValue.discardStrayMoveEvents == true)
        #expect(Defaults.DefaultValue.failFastOnEventWindowMismatch == false)
        #expect(Defaults.DefaultValue.axMessagingTimeout == 1.0)
    }
}
