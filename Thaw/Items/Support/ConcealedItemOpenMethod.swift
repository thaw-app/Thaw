//
//  ConcealedItemOpenMethod.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Apps differ in which concealed-menu methods they answer.
/// Moving beside Thaw is unsafe: the agent refuses the concealed move back, stranding the item.
nonisolated enum ConcealedItemOpenMethod: String, CaseIterable, Sendable {
    /// Accessibility press on the parked item. Nothing appears in the bar.
    case pressInPlace
    /// Reveal the item where it sits and click it there.
    case revealInPlace

    /// Try the learned method first, then the cheapest; right clicks skip press because it opens the default action.
    /// showInMenuBar overrides learning to reveal first, falling back to press if the click fails.
    static func openMethodOrder(
        for mouseButton: CGMouseButton,
        learned: ConcealedItemOpenMethod?,
        showInMenuBar: Bool = false
    ) -> [ConcealedItemOpenMethod] {
        if mouseButton == .right {
            return [.revealInPlace]
        }
        if showInMenuBar {
            return [.revealInPlace, .pressInPlace]
        }
        let candidates: [ConcealedItemOpenMethod] = [.pressInPlace, .revealInPlace]
        guard let learned else { return candidates }
        return [learned] + candidates.filter { $0 != learned }
    }
}
