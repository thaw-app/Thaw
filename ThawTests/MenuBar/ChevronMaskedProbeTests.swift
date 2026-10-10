//
//  ChevronMaskedProbeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Masked probes do not read the strip; retain a known chevron or unexpired absence, otherwise report unavailable.
@Suite("Chevron masked probe")
struct ChevronMaskedProbeTests {
    @Test("A known chevron stands")
    func knownChevronStands() {
        let hint = CGRect(x: 1200, y: 0, width: 24, height: 24)
        let now = ContinuousClock.now
        let observation = MenuBarItemAXProvider.chevronObservationWhileMasked(
            hint: hint,
            lastAbsentAt: nil,
            now: now
        )
        #expect(observation == .present([hint]))
    }

    @Test("An absence inside its cooldown stands")
    func absenceInsideCooldownStands() {
        let now = ContinuousClock.now
        let observation = MenuBarItemAXProvider.chevronObservationWhileMasked(
            hint: nil,
            lastAbsentAt: now - .seconds(1),
            now: now
        )
        #expect(observation == .absent)
    }

    @Test("An absence past its cooldown is unavailable")
    func absencePastCooldownIsUnavailable() {
        let now = ContinuousClock.now
        let observation = MenuBarItemAXProvider.chevronObservationWhileMasked(
            hint: nil,
            lastAbsentAt: now - .seconds(13),
            now: now
        )
        #expect(observation == .unavailable)
    }

    @Test("No hint and no absence is unavailable")
    func noHintNoAbsenceIsUnavailable() {
        let observation = MenuBarItemAXProvider.chevronObservationWhileMasked(
            hint: nil,
            lastAbsentAt: nil,
            now: .now
        )
        #expect(observation == .unavailable)
    }
}
