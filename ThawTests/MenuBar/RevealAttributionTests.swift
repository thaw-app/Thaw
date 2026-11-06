//
//  RevealAttributionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import MenuBarModel
import Testing
@testable import Thaw

/// A reveal Thaw makes by itself carries the policy cause until the section is hidden again.
@MainActor
@Suite("Reveal attribution")
struct RevealAttributionTests {
    @Test("With no policy reveal the causes are the user's")
    func defaultsToTheUser() {
        let attribution = RevealAttribution()

        #expect(attribution.preRevealCause == .revealStarting)
        #expect(attribution.reconcileCause == .sectionRevealed)
    }

    @Test("A policy reveal carries the policy cause, before the section changes and after show returns")
    func policyRevealIsMarked() {
        let attribution = RevealAttribution()
        var preRevealCause: RepairOrchestrator.Cause?

        attribution.policy {
            // The kit pins the order before it changes the revealed section.
            preRevealCause = attribution.preRevealCause
            attribution.noteRevealedSection(.hidden)
        }

        #expect(preRevealCause == .policyReveal)
        #expect(attribution.reconcileCause == .policyReveal)
        #expect(attribution.preRevealCause == .revealStarting)
    }

    @Test("The mark lasts until the revealed section is nil, then the causes are the user's again")
    func markLastsUntilHide() {
        let attribution = RevealAttribution()
        attribution.policy { attribution.noteRevealedSection(.hidden) }
        #expect(attribution.reconcileCause == .policyReveal)

        attribution.noteRevealedSection(nil)

        #expect(attribution.preRevealCause == .revealStarting)
        #expect(attribution.reconcileCause == .sectionRevealed)
    }

    @Test("A policy hide clears the mark too")
    func policyHideClears() {
        let attribution = RevealAttribution()
        attribution.policy { attribution.noteRevealedSection(.hidden) }

        attribution.policy { attribution.noteRevealedSection(nil) }

        #expect(attribution.reconcileCause == .sectionRevealed)
    }

    @Test("A user reveal while a policy reveal is up takes the reveal over")
    func userRevealOverwrites() {
        let attribution = RevealAttribution()
        attribution.policy { attribution.noteRevealedSection(.hidden) }

        #expect(attribution.preRevealCause == .revealStarting)
        attribution.noteRevealedSection(.alwaysHidden)

        #expect(attribution.reconcileCause == .sectionRevealed)
    }

    @Test("A policy call that changes nothing leaves the user's reveal the user's")
    func policyNoOpKeepsTheUserReveal() {
        let attribution = RevealAttribution()
        attribution.noteRevealedSection(.hidden)

        attribution.policy {}

        #expect(attribution.reconcileCause == .sectionRevealed)
    }

    @Test("The same section published again outside a policy call leaves the mark alone")
    func repeatedValueKeepsTheMark() {
        let attribution = RevealAttribution()
        attribution.policy { attribution.noteRevealedSection(.hidden) }

        attribution.noteRevealedSection(.hidden)

        #expect(attribution.reconcileCause == .policyReveal)
    }

    @Test("A policy call inside another keeps the mark until the outer one returns")
    func nestedPolicyCalls() {
        let attribution = RevealAttribution()
        var innerCause: RepairOrchestrator.Cause?

        attribution.policy {
            attribution.policy {}
            innerCause = attribution.preRevealCause
        }

        #expect(innerCause == .policyReveal)
        #expect(attribution.preRevealCause == .revealStarting)
    }

    @Test("The revealed section is read from a publisher as it changes")
    func observesThePublisher() {
        let attribution = RevealAttribution()
        let revealed = PassthroughSubject<MenuBarSectionName?, Never>()
        attribution.observe(revealed.eraseToAnyPublisher())

        attribution.policy { revealed.send(.hidden) }
        #expect(attribution.reconcileCause == .policyReveal)

        revealed.send(nil)
        #expect(attribution.reconcileCause == .sectionRevealed)
    }

    @Test("A policy reveal through the orchestrator leaves a planned automatic pass its turn")
    func policyRevealLeavesAPlannedPass() async {
        let attribution = RevealAttribution()
        let repairs = RepairOrchestrator()
        repairs.request(.postRestrictionRepair, cause: .restrictionChanged)

        attribution.policy {
            _ = repairs.writeNow(.preRevealOrder, cause: attribution.preRevealCause) { $0.door }
            attribution.noteRevealedSection(.hidden)
        }
        repairs.request(.revealReconcile, cause: attribution.reconcileCause)

        let hold = await repairs.enter(.postRestrictionRepair)
        #expect(hold != nil)
        if let hold {
            repairs.leave(hold)
        }
    }
}
