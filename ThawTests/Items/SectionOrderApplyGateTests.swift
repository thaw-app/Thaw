//
//  SectionOrderApplyGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

/// The eight skip gates in evaluation order: the first refusing gate wins,
/// and authored edits, reveals and repairs carry their exemptions.
struct SectionOrderApplyGateTests {
    private func makeRequest(
        isCancelled: Bool = false,
        controllerRevealedSection: MenuBarSection.Name? = nil,
        revealedSection: MenuBarSection.Name? = nil,
        circuitBreakerOpen: Bool = false,
        reason: LayoutChangeReason = .revealRestore,
        arrangementIsManual: Bool = false,
        isExplicitLayoutEdit: Bool = false,
        nativeMenuBarDeferred: Bool = false,
        isWithinSettleWindow: Bool = false,
        repairAfterRestriction: Bool = false,
        wrapsPastNotch: String? = nil,
        budgetExhausted: Bool = false,
        prefersPositionWrites: Bool = true
    ) -> SectionOrderApplyGate.Request {
        .init(
            isCancelled: isCancelled,
            controllerRevealedSection: controllerRevealedSection,
            revealedSection: revealedSection,
            circuitBreakerOpen: circuitBreakerOpen,
            reason: reason,
            arrangementIsManual: arrangementIsManual,
            isExplicitLayoutEdit: isExplicitLayoutEdit,
            nativeMenuBarDeferred: nativeMenuBarDeferred,
            isWithinSettleWindow: isWithinSettleWindow,
            repairAfterRestriction: repairAfterRestriction,
            applicationMenuWrapsPastNotch: { wrapsPastNotch },
            isConvergenceBudgetExhausted: { budgetExhausted },
            prefersPositionWrites: prefersPositionWrites
        )
    }

    @Test("A clear automatic pass proceeds")
    func proceeds() {
        #expect(SectionOrderApplyGate.firstRejection(makeRequest()) == nil)
    }

    @Test("Cancellation and reveal mismatch refuse first, before any other gate")
    func cancellationAndReveal() {
        #expect(
            SectionOrderApplyGate.firstRejection(makeRequest(isCancelled: true)) == .cancelled
        )
        #expect(
            SectionOrderApplyGate.firstRejection(
                makeRequest(
                    isCancelled: true,
                    circuitBreakerOpen: true,
                    arrangementIsManual: true
                )
            ) == .cancelled
        )
        #expect(
            SectionOrderApplyGate.firstRejection(
                makeRequest(
                    controllerRevealedSection: .visible,
                    revealedSection: .hidden
                )
            ) == .revealMismatch
        )
        // A matching reveal is not a mismatch.
        #expect(
            SectionOrderApplyGate.firstRejection(
                makeRequest(
                    controllerRevealedSection: .hidden,
                    revealedSection: .hidden
                )
            ) == nil
        )
    }

    @Test("The circuit breaker stops automatic passes but not user actions or authored edits")
    func circuitBreaker() {
        #expect(
            SectionOrderApplyGate.firstRejection(
                makeRequest(circuitBreakerOpen: true, reason: .externalChange)
            ) == .circuitBreakerOpen
        )
        // A reveal restore is user-initiated without being an authored edit,
        // so it runs while the breaker is open.
        #expect(
            SectionOrderApplyGate.firstRejection(
                makeRequest(circuitBreakerOpen: true, reason: .revealRestore)
            ) == nil
        )
        #expect(
            SectionOrderApplyGate.firstRejection(
                makeRequest(circuitBreakerOpen: true, reason: .userReorder)
            ) == nil
        )
    }

    @Test("A reason that accepts the settled order never enforces")
    func reasonPolicy() {
        #expect(
            SectionOrderApplyGate.firstRejection(makeRequest(reason: .externalChange))
                == .reasonAcceptsSettledOrder
        )
        #expect(
            SectionOrderApplyGate.firstRejection(makeRequest(reason: .userReorder)) == nil
        )
    }

    @Test("Manual arrangement lets the user's own Layout edit through")
    func manualArrangementAllowsAnExplicitLayoutEdit() {
        #expect(
            SectionOrderApplyGate.firstRejection(
                makeRequest(reason: .userReorder, arrangementIsManual: true, isExplicitLayoutEdit: true)
            ) == nil
        )
    }

    @Test("Manual arrangement refuses a user reorder that no Layout edit carries")
    func manualArrangementRefusesAnUnmarkedReorder() {
        #expect(
            SectionOrderApplyGate.firstRejection(
                makeRequest(reason: .userReorder, arrangementIsManual: true)
            ) == .manualArrangement
        )
    }

    @Test(
        "Manual arrangement refuses every automatic reason, even inside a Layout edit's task",
        arguments: [LayoutChangeReason.profileApply, .revealRestore, .settingChange, .arrivalRestore],
        [false, true]
    )
    func manualArrangementRefusesAutomaticReasons(reason: LayoutChangeReason, isExplicitLayoutEdit: Bool) {
        #expect(
            SectionOrderApplyGate.firstRejection(
                makeRequest(
                    reason: reason,
                    arrangementIsManual: true,
                    isExplicitLayoutEdit: isExplicitLayoutEdit
                )
            ) == .manualArrangement
        )
    }

    @Test("An observed change moves nothing in Manual either", arguments: [false, true])
    func manualArrangementNeverEnforcesAnObservedChange(isExplicitLayoutEdit: Bool) {
        #expect(
            SectionOrderApplyGate.firstRejection(
                makeRequest(
                    reason: .externalChange,
                    arrangementIsManual: true,
                    isExplicitLayoutEdit: isExplicitLayoutEdit
                )
            ) == .reasonAcceptsSettledOrder
        )
    }

    @Test("The Layout edit mark changes nothing in Automatic")
    func automaticIgnoresTheLayoutEditMark() {
        #expect(
            SectionOrderApplyGate.firstRejection(
                makeRequest(reason: .revealRestore, isExplicitLayoutEdit: true)
            ) == nil
        )
    }

    @Test("The settle window defers only automatic visible-section passes")
    func settleWindow() {
        #expect(
            SectionOrderApplyGate.firstRejection(
                makeRequest(isWithinSettleWindow: true)
            ) == .restrictionReflowSettleWindow
        )
        // An authored edit runs inside the window.
        #expect(
            SectionOrderApplyGate.firstRejection(
                makeRequest(reason: .profileApply, isWithinSettleWindow: true)
            ) == nil
        )
        // A reveal continuation runs inside the window.
        #expect(
            SectionOrderApplyGate.firstRejection(
                makeRequest(controllerRevealedSection: .hidden, revealedSection: .hidden, isWithinSettleWindow: true)
            ) == nil
        )
        // So does a post-restriction repair.
        #expect(
            SectionOrderApplyGate.firstRejection(
                makeRequest(isWithinSettleWindow: true, repairAfterRestriction: true)
            ) == nil
        )
    }

    @Test("The notch lane gate skips with the display detail, unless authored")
    func notchLane() {
        let rejection = SectionOrderApplyGate.firstRejection(
            makeRequest(wrapsPastNotch: "1234")
        )
        guard case let .applicationMenuWrapsPastNotch(displayID) = rejection else {
            Issue.record("expected the lane gate, got \(String(describing: rejection))")
            return
        }
        #expect(displayID == "1234")
        #expect(
            SectionOrderApplyGate.firstRejection(
                makeRequest(reason: .userReorder, wrapsPastNotch: "1234")
            ) == nil
        )
    }

    @Test("The budget gate fires only for cursor-free automatic visible passes")
    func budget() {
        let base = makeRequest(
            budgetExhausted: true,
            prefersPositionWrites: true
        )
        #expect(SectionOrderApplyGate.firstRejection(base) == .convergenceBudgetExhausted)
        // Authored edits, reveals and repairs are exempt.
        #expect(
            SectionOrderApplyGate.firstRejection(
                makeRequest(reason: .profileApply, budgetExhausted: true, prefersPositionWrites: true)
            ) == nil
        )
        #expect(
            SectionOrderApplyGate.firstRejection(
                makeRequest(
                    controllerRevealedSection: .hidden,
                    revealedSection: .hidden,
                    budgetExhausted: true,
                    prefersPositionWrites: true
                )
            ) == nil
        )
        #expect(
            SectionOrderApplyGate.firstRejection(
                makeRequest(
                    repairAfterRestriction: true,
                    budgetExhausted: true,
                    prefersPositionWrites: true
                )
            ) == nil
        )
        // Cursor-free means the drag channel is out of the picture; a pass
        // that writes positions through the store is what the budget bounds.
        #expect(
            SectionOrderApplyGate.firstRejection(
                makeRequest(budgetExhausted: true, prefersPositionWrites: false)
            ) == nil
        )
    }

    @Test("A lazy condition is never read once an earlier gate refuses")
    func lazyConditions() {
        var budgetRead = false
        let request = SectionOrderApplyGate.Request(
            isCancelled: false,
            controllerRevealedSection: nil,
            revealedSection: nil,
            circuitBreakerOpen: true,
            reason: .externalChange,
            arrangementIsManual: false,
            isExplicitLayoutEdit: false,
            nativeMenuBarDeferred: false,
            isWithinSettleWindow: false,
            repairAfterRestriction: false,
            applicationMenuWrapsPastNotch: { nil },
            isConvergenceBudgetExhausted: {
                budgetRead = true
                return true
            },
            prefersPositionWrites: true
        )
        #expect(SectionOrderApplyGate.firstRejection(request) == .circuitBreakerOpen)
        #expect(!budgetRead)
    }
}
