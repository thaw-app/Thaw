//
//  SectionOrderApplyGate.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Pure section-order policy: snapshot live state into Request to get the first refusal, or nil to proceed.
nonisolated enum SectionOrderApplyGate {
    /// Everything the gates read, snapshotted by the caller.
    nonisolated struct Request {
        let isCancelled: Bool
        let controllerRevealedSection: MenuBarSection.Name?
        let revealedSection: MenuBarSection.Name?
        let circuitBreakerOpen: Bool
        let reason: LayoutChangeReason
        let arrangementIsManual: Bool
        /// Whether the calling task carries an explicit Layout edit; see ExplicitLayoutEdit.
        let isExplicitLayoutEdit: Bool
        let nativeMenuBarDeferred: Bool
        let isWithinSettleWindow: Bool
        let repairAfterRestriction: Bool
        /// Display log detail if app menus wrap past the notch, nil otherwise; consulted only for non-authored passes.
        let applicationMenuWrapsPastNotch: () -> String?
        /// Consulted only for cursor-free automatic visible passes, excluding authored edits and repairs.
        let isConvergenceBudgetExhausted: () -> Bool
        let prefersPositionWrites: Bool

        init(
            isCancelled: Bool,
            controllerRevealedSection: MenuBarSection.Name?,
            revealedSection: MenuBarSection.Name?,
            circuitBreakerOpen: Bool,
            reason: LayoutChangeReason,
            arrangementIsManual: Bool,
            isExplicitLayoutEdit: Bool,
            nativeMenuBarDeferred: Bool,
            isWithinSettleWindow: Bool,
            repairAfterRestriction: Bool,
            applicationMenuWrapsPastNotch: @escaping () -> String?,
            isConvergenceBudgetExhausted: @escaping () -> Bool,
            prefersPositionWrites: Bool
        ) {
            self.isCancelled = isCancelled
            self.controllerRevealedSection = controllerRevealedSection
            self.revealedSection = revealedSection
            self.circuitBreakerOpen = circuitBreakerOpen
            self.reason = reason
            self.arrangementIsManual = arrangementIsManual
            self.isExplicitLayoutEdit = isExplicitLayoutEdit
            self.nativeMenuBarDeferred = nativeMenuBarDeferred
            self.isWithinSettleWindow = isWithinSettleWindow
            self.repairAfterRestriction = repairAfterRestriction
            self.applicationMenuWrapsPastNotch = applicationMenuWrapsPastNotch
            self.isConvergenceBudgetExhausted = isConvergenceBudgetExhausted
            self.prefersPositionWrites = prefersPositionWrites
        }
    }

    /// Refusals in evaluation order.
    nonisolated enum Rejection: Equatable {
        /// The task died, or a revealed section's pass found the reveal gone.
        case cancelled
        case revealMismatch
        /// Stops failed automatic drag churn; authored edits and user actions still run.
        case circuitBreakerOpen
        /// The reason accepts the settled order and may not move anything.
        case reasonAcceptsSettledOrder
        /// Manual arrangement forbids every pass but the user's own Layout edit: a profile, reveal, or repair still moves nothing.
        case manualArrangement
        /// The native menu bar is unavailable or mid-transition.
        case nativeMenuBarUnavailable
        /// Defers idle visible reorders, not repairs, authored edits, or the user's hidden-section reveal.
        /// Reveals start the reflow window themselves; blocking them would delay the requested order.
        case restrictionReflowSettleWindow
        /// Wrapped app menus collapse the trailing lane; boundary drags fail with cannotComplete.
        /// Authored edits still run for the waiting user; reveals and repairs wait for menus to retreat.
        case applicationMenuWrapsPastNotch(displayID: String)
        /// Bounds automatic convergence after an authored edit to avoid repeated visible boundary drags.
        /// Authored, reveal, repair, and cursor-free store passes are exempt from this visibility budget.
        case convergenceBudgetExhausted
    }

    /// The first refusing gate, or nil when the pass may run.
    static nonisolated func firstRejection(_ request: Request) -> Rejection? {
        if request.isCancelled {
            return .cancelled
        }
        if request.revealedSection != nil,
           request.controllerRevealedSection != request.revealedSection
        {
            return .revealMismatch
        }
        if request.circuitBreakerOpen, !request.reason.isUserInitiated, !request.reason.isAuthoredEdit {
            return .circuitBreakerOpen
        }
        if !request.reason.permitsOrderEnforcement {
            return .reasonAcceptsSettledOrder
        }
        if ExplicitLayoutEdit.manualArrangementForbids(
            arrangementIsManual: request.arrangementIsManual,
            isExplicitLayoutEdit: request.isExplicitLayoutEdit,
            reason: request.reason
        ) {
            return .manualArrangement
        }
        if request.nativeMenuBarDeferred {
            return .nativeMenuBarUnavailable
        }
        if !request.repairAfterRestriction,
           !request.reason.isAuthoredEdit,
           request.revealedSection == nil,
           request.isWithinSettleWindow
        {
            return .restrictionReflowSettleWindow
        }
        if !request.reason.isAuthoredEdit,
           let displayID = request.applicationMenuWrapsPastNotch()
        {
            return .applicationMenuWrapsPastNotch(displayID: displayID)
        }
        if request.prefersPositionWrites,
           !request.reason.isAuthoredEdit,
           request.revealedSection == nil,
           !request.repairAfterRestriction,
           request.isConvergenceBudgetExhausted()
        {
            return .convergenceBudgetExhausted
        }
        return nil
    }
}
