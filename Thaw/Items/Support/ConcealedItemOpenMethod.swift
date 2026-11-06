//
//  ConcealedItemOpenMethod.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Apps differ in which concealed-menu methods they answer.
/// Moving beside Thaw is unsafe: the agent refuses the concealed move back, stranding the item.
///
/// A left click climbs three stages, each tried only when the one before didn't open the item:
/// press in place, reveal and press, and reveal and click, the only one that moves the pointer.
nonisolated enum ConcealedItemOpenMethod: String, CaseIterable, Sendable {
    /// Accessibility press on the item, shown where it sits for the press: a press on an
    /// item the bar does not draw leaves the bar stuck on screen whenever it should hide.
    case pressInPlace
    /// Reveal the item where it sits and press the element drawn there, without moving the
    /// pointer. Items learned as revealInPlace, which also clicked for real, are no longer read:
    /// starting them here would fail one that needs the click, so they start over from the press.
    case revealAndPress
    /// Reveal the item where it sits and click it for real, which moves the pointer.
    case revealAndClick
    /// AXShowMenu on the parked item, the menu a right click opens. Right clicks only.
    case showMenuInPlace

    /// The methods to try in turn. Methods in one attempt share a reveal: a press that isn't
    /// seen working falls through to the click without hiding the item in between.
    ///
    /// A left click starts at the learned stage. Reveal and press, once learned, never falls
    /// through to the real click: a press that worked before and isn't seen this time leaves
    /// the item shown to be clicked. Right clicks skip press, which opens the default action;
    /// showInMenuBar reveals first.
    static func openAttempts(
        for mouseButton: CGMouseButton,
        learned: ConcealedItemOpenMethod?,
        showInMenuBar: Bool = false
    ) -> [[ConcealedItemOpenMethod]] {
        if mouseButton == .right {
            return showInMenuBar ? [[.revealAndClick]] : [[.showMenuInPlace], [.revealAndClick]]
        }
        let reveal: [ConcealedItemOpenMethod] = switch learned {
        case .revealAndPress: [.revealAndPress]
        case .revealAndClick: [.revealAndClick]
        // A right click's method would open the wrong menu, so it counts as nothing learned.
        case .pressInPlace, .showMenuInPlace, nil: [.revealAndPress, .revealAndClick]
        }
        // A learned reveal goes first.
        if showInMenuBar || reveal.count == 1 {
            return [reveal, [.pressInPlace]]
        }
        return [[.pressInPlace], reveal]
    }
}
