//
//  ChevronMaskedProbeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
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

    @Test("An external display trusts an empty sweep for longer than a built-in one")
    func externalDisplayIsSweptLessOften() {
        let builtIn = MenuBarItemAXProvider.chevronAbsenceCooldown(isBuiltIn: true)
        let external = MenuBarItemAXProvider.chevronAbsenceCooldown(isBuiltIn: false)
        #expect(builtIn > .seconds(5), "must outlast the 5 s refresh backstop")
        #expect(external > builtIn)

        let now = ContinuousClock.now
        let observation = MenuBarItemAXProvider.chevronObservationWhileMasked(
            hint: nil,
            lastAbsentAt: now - .seconds(30),
            now: now,
            cooldown: external
        )
        #expect(observation == .absent)
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

    @Test("Thaw's own menus in the bar hold the probe; another app's or none do not")
    func ownMenusHoldTheProbe() {
        #expect(MenuBarItemAXProvider.isThawTheMenuBarOwner(ProcessInfo.processInfo.processIdentifier))
        #expect(!MenuBarItemAXProvider.isThawTheMenuBarOwner(1))
        #expect(!MenuBarItemAXProvider.isThawTheMenuBarOwner(nil))
    }
}
