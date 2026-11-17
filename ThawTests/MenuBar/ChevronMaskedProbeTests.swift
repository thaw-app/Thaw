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

/// Masked probes do not read the strip. A walk that sees the chevron on this display answers;
/// otherwise retain a known chevron or unexpired absence, else report unavailable.
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

    @Test("A walk that rules the chevron out overrides a held sighting")
    func walkOverridesHeldSighting() {
        let observation = MenuBarItemAXProvider.chevronObservationWhileMasked(
            hint: CGRect(x: 1007.5, y: 1, width: 18, height: 30),
            lastAbsentAt: nil,
            now: .now,
            walkRulesOutChevron: true
        )
        #expect(observation == .absent)
    }

    @Test("A walk that rules the chevron out answers when nothing is held")
    func walkAnswersWithNothingHeld() {
        let observation = MenuBarItemAXProvider.chevronObservationWhileMasked(
            hint: nil,
            lastAbsentAt: nil,
            now: .now,
            walkRulesOutChevron: true
        )
        #expect(observation == .absent)
    }

    @Test("The walk rules the chevron out only where it has seen one, and only from a complete read")
    func walkRulesOutOnlyFromACompleteRead() {
        #expect(MenuBarItemAXProvider.walkRulesOutChevron(
            walkHasSeenChevron: true, attributeReadFailed: false, unframedControlCount: 0
        ))
        #expect(!MenuBarItemAXProvider.walkRulesOutChevron(
            walkHasSeenChevron: false, attributeReadFailed: false, unframedControlCount: 0
        ), "a notchless display draws its chevron outside the extras bar")
        #expect(!MenuBarItemAXProvider.walkRulesOutChevron(
            walkHasSeenChevron: true, attributeReadFailed: true, unframedControlCount: 0
        ))
        #expect(!MenuBarItemAXProvider.walkRulesOutChevron(
            walkHasSeenChevron: true, attributeReadFailed: false, unframedControlCount: 1
        ), "a control without a usable frame is not proof it is gone")
    }

    @Test("Thaw's own menus in the bar hold the probe; another app's or none do not")
    func ownMenusHoldTheProbe() {
        #expect(MenuBarItemAXProvider.isThawTheMenuBarOwner(ProcessInfo.processInfo.processIdentifier))
        #expect(!MenuBarItemAXProvider.isThawTheMenuBarOwner(1))
        #expect(!MenuBarItemAXProvider.isThawTheMenuBarOwner(nil))
    }
}
