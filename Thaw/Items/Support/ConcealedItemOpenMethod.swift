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
    /// Accessibility press on the item, shown where it sits for the press: a press on an
    /// item the bar does not draw leaves the bar stuck on screen whenever it should hide.
    case pressInPlace
    /// Reveal the item where it sits and click it there.
    case revealInPlace
    /// AXShowMenu on the parked item, the menu a right click opens. Right clicks only.
    case showMenuInPlace

    /// The learned method first, then the cheapest. Right clicks skip press, which opens the default action;
    /// showInMenuBar reveals first.
    static func openMethodOrder(
        for mouseButton: CGMouseButton,
        learned: ConcealedItemOpenMethod?,
        showInMenuBar: Bool = false
    ) -> [ConcealedItemOpenMethod] {
        if mouseButton == .right {
            return showInMenuBar ? [.revealInPlace] : [.showMenuInPlace, .revealInPlace]
        }
        if showInMenuBar {
            return [.revealInPlace, .pressInPlace]
        }
        let candidates: [ConcealedItemOpenMethod] = [.pressInPlace, .revealInPlace]
        // A right click's method would open the wrong menu on a left click.
        guard let learned, learned != .showMenuInPlace else { return candidates }
        return [learned] + candidates.filter { $0 != learned }
    }
}
