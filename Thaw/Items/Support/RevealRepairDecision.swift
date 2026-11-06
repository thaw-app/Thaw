//
//  RevealRepairDecision.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Whether a reveal's repair moves an item back across the Hidden divider.
nonisolated enum RevealRepairDecision {
    static func shouldMove(method: HidingMethod, switchedOnForReveal: Bool, isMisplaced: Bool) -> Bool {
        isMisplaced && !(method == .native && switchedOnForReveal)
    }
}
