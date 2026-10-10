//
//  OverflowRebalanceRequest.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// What one overflow rebalance was asked to do, and how requests coalesce while a rebalance is pending.
/// Pure merge policy for timing-independent tests: explicit reasons win and immediacy is sticky.
nonisolated struct OverflowRebalanceRequest: Equatable, Sendable {
    var reason: LayoutChangeReason
    var immediate: Bool

    func merged(into pending: OverflowRebalanceRequest?) -> OverflowRebalanceRequest {
        guard let pending else { return self }
        return OverflowRebalanceRequest(
            reason: pending.reason.permitsOrderEnforcement ? pending.reason : reason,
            immediate: pending.immediate || immediate
        )
    }
}
