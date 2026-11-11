//
//  MenuBarItemManager+WriteHoldSituation.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel

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
        let barHolds = barSettling.holds(for: .structuralPass)
        situation.startupSettling = barHolds.contains(.settling)
        situation.circuitBreakerOpen = moveCircuitBreaker.isOpen
        situation.notificationCenterSuspended = isNotificationCenterLayoutSuspended
        situation.userDragging = appState?.isDraggingMenuBarItem ?? false
        situation.profileApplying = isApplyingProfileLayout
        situation.membershipReadPending = manualMembershipTask != nil
        situation.layoutPublicationStale = !layoutPublication.canPublish(generation: layoutPublication.generation)
        situation.sectionRevealed = appState?.menuBarManager.sectionController.revealedSection != nil
        situation.revealTransitionActive = barHolds.contains(.revealTransition)
        let barDisplayID = Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
        situation.barOnUncachedDisplay = itemDisplayID.map { $0 != barDisplayID } ?? false
        situation.barReadIncomplete = !cacheCycleState.lastRead.isComplete
        return situation
    }

    /// Reads the bar in full when it moved to a display the cache hasn't followed: only a full
    /// read moves the cache, and an unchanged window list never asks for one.
    func readBarIfItMoved(_ situation: WriteHold.Situation) {
        guard situation.barOnUncachedDisplay else { return }
        Task { await cacheItemsRegardless() }
    }
}
