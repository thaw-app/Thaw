//
//  MenuBarItemManager+WriteHoldSituation.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

extension MenuBarItemManager {
    /// Manual arrangement turns the pass off, except to re-lay a stranded
    /// visible control item, which the user cannot drag back.
    var manualArrangementAllowsControlRelay: Bool {
        guard arrangementIsManual else { return true }
        let settled = itemCache.managedItems
        return !settled.isEmpty && ControlOrderRules.visibleControlIsStranded(among: settled)
    }

    /// Reads the manager's flags into the situation the structural
    /// normalization pass checks.
    func structuralNormalizationSituation() -> WriteHold.Situation {
        var situation = WriteHold.Situation()
        situation.startupSettling = isInStartupSettling
        situation.circuitBreakerOpen = moveCircuitBreaker.isOpen
        situation.notificationCenterSuspended = isNotificationCenterLayoutSuspended
        situation.userDragging = appState?.isDraggingMenuBarItem ?? false
        situation.profileApplying = isApplyingProfileLayout
        situation.membershipReadPending = manualMembershipTask != nil
        situation.layoutPublicationStale = !layoutPublication.canPublish(generation: layoutPublication.generation)
        situation.sectionRevealed = appState?.menuBarManager.sectionController.revealedSection != nil
        situation.revealTransitionActive = appState?.menuBarManager.isRevealHideTransitionActive ?? false
        return situation
    }
}
