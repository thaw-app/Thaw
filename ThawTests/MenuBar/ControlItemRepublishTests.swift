//
//  ControlItemRepublishTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import MenuBarModel
import Testing
@testable import Thaw

/// The budget that keeps a status-item re-register bounded, and the
/// tag-to-section mapping that finds the item to re-register.
struct ControlItemRepublishTests {
    @Test("Fresh item republishes on the first attempt")
    func freshItemRepublishes() {
        let decision = ControlItem.republishDecision(priorCount: 0)
        #expect(decision == .republish(attempt: 1))
    }

    @Test("Second unseat still republishes")
    func secondUnseatRepublishes() {
        let decision = ControlItem.republishDecision(priorCount: 1)
        #expect(decision == .republish(attempt: 2))
    }

    /// A host rejecting every registered window is a fault re-registering
    /// cannot fix, so the budget runs out instead of churning the bar.
    @Test("Budget exhausts at the ceiling")
    func budgetExhausts() {
        #expect(ControlItem.republishDecision(priorCount: 2) == .exhausted)
        #expect(ControlItem.republishDecision(priorCount: 5) == .exhausted)
    }

    /// Only a switch read as off is a denial; an unreadable list must keep
    /// the re-register alive, since nothing says it cannot work.
    @Test("Only a switch read as off counts as a denial")
    func placementBlockFollowsSwitch() {
        #expect(ControlItem.placementBlock(systemAllowsThaw: false) == .deniedBySystem)
        #expect(ControlItem.placementBlock(systemAllowsThaw: true) == .unknown)
        #expect(ControlItem.placementBlock(systemAllowsThaw: nil) == .unknown)
    }

    @Test("Custom ceiling is honored")
    func customCeiling() {
        #expect(ControlItem.republishDecision(priorCount: 2, ceiling: 3) == .republish(attempt: 3))
        #expect(ControlItem.republishDecision(priorCount: 3, ceiling: 3) == .exhausted)
    }

    /// A spent budget re-arms once the cooldown elapses instead of latching
    /// off for the session.
    @Test("Spent budget re-arms after the cooldown")
    func spentBudgetRearms() {
        #expect(
            ControlItem.republishDecision(
                priorCount: 2,
                elapsedSinceLastAttempt: .seconds(60)
            ) == .republish(attempt: 1)
        )
    }

    @Test("Spent budget stays spent inside the cooldown")
    func spentBudgetStaysSpentInsideCooldown() {
        #expect(
            ControlItem.republishDecision(
                priorCount: 2,
                elapsedSinceLastAttempt: .seconds(59)
            ) == .exhausted
        )
    }

    /// No recorded last attempt means the cooldown cannot be evaluated; the
    /// budget stays spent rather than guessing.
    @Test("Missing last attempt keeps the budget spent")
    func missingLastAttemptKeepsSpent() {
        #expect(
            ControlItem.republishDecision(priorCount: 2, elapsedSinceLastAttempt: nil) == .exhausted
        )
    }

    /// The re-arm starts a fresh cycle, not a continuation of the spent one.
    @Test("Re-arm attempt numbering restarts at one")
    func rearmRestartsNumbering() {
        #expect(
            ControlItem.republishDecision(
                priorCount: 5,
                elapsedSinceLastAttempt: .seconds(300)
            ) == .republish(attempt: 1)
        )
    }

    @Test("Custom re-arm cooldown is honored")
    func customRearmCooldown() {
        #expect(
            ControlItem.republishDecision(
                priorCount: 2,
                elapsedSinceLastAttempt: .seconds(10),
                ceiling: 2,
                rearmCooldown: .seconds(5)
            ) == .republish(attempt: 1)
        )
        #expect(
            ControlItem.republishDecision(
                priorCount: 2,
                elapsedSinceLastAttempt: .seconds(4),
                ceiling: 2,
                rearmCooldown: .seconds(5)
            ) == .exhausted
        )
    }

    @Test("Control item tags map to their sections")
    func controlTagsMapToSections() {
        #expect(MenuBarItemManager.controlItemSectionName(for: .visibleControlItem) == .visible)
        #expect(MenuBarItemManager.controlItemSectionName(for: .hiddenControlItem) == .hidden)
        #expect(MenuBarItemManager.controlItemSectionName(for: .alwaysHiddenControlItem) == .alwaysHidden)
    }

    /// Only Thaw's own items can be re-registered; anything else must fall
    /// through to the ordinary move recovery.
    @Test("Foreign tags do not map to a section")
    func foreignTagsDoNotMap() {
        #expect(MenuBarItemManager.controlItemSectionName(for: .audioVideoModule) == nil)
    }

    /// Escalate by cost: position refresh, visibility toggle, then full status-item registration.
    @Test("Off-band recovery escalates cheapest rung first")
    func offBandLadderOrder() {
        #expect(ControlItem.offBandRecoveryAction(takenInCycle: 0, cycle: 0) == .nudge)
        #expect(ControlItem.offBandRecoveryAction(takenInCycle: 1, cycle: 0) == .toggleVisibility)
        #expect(ControlItem.offBandRecoveryAction(takenInCycle: 2, cycle: 0) == .republishStatusItem)
    }

    /// A fresh cycle after a re-register starts back at the cheapest rung.
    @Test("Ladder restarts at the nudge in a new cycle")
    func ladderRestartsPerCycle() {
        #expect(ControlItem.offBandRecoveryAction(takenInCycle: 0, cycle: 1) == .nudge)
        #expect(ControlItem.offBandRecoveryAction(takenInCycle: 2, cycle: 1) == .republishStatusItem)
    }

    /// Two full cycles is the session budget: beyond that the host is
    /// rejecting every placement and more attempts would only churn the bar.
    @Test("Ladder exhausts at the cycle ceiling")
    func ladderExhausts() {
        #expect(ControlItem.offBandRecoveryAction(takenInCycle: 0, cycle: 2) == .exhausted)
        #expect(ControlItem.offBandRecoveryAction(takenInCycle: 2, cycle: 5) == .exhausted)
    }
}
