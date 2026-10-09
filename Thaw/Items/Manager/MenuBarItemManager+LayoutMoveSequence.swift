//
//  MenuBarItemManager+LayoutMoveSequence.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import PlatformRuntimeKit

// MARK: - Layout Move Sequence

extension MenuBarItemManager {
    /// See Defaults.Key.useLCSSectionOrderPlanner.
    static var usesLCSSectionOrderPlanner: Bool {
        Defaults.bool(forKey: .useLCSSectionOrderPlanner)
    }

    /// The hidden and always-hidden divider window IDs, read from the live
    /// control items. A zero-length divider has no window, so either is nil
    /// when its section is collapsed.
    func liveControlItemWindowIDs() -> (hidden: CGWindowID?, alwaysHidden: CGWindowID?) {
        let hidden = appState?.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let alwaysHidden = appState?.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        return (hidden, alwaysHidden)
    }

    /// The divider pair resolved from items, or nil when the hidden
    /// divider is not on the bar.
    func controlItemPair(in items: [MenuBarItem]) -> ControlItemPair? {
        let windowIDs = liveControlItemWindowIDs()
        var discovery = items
        return ControlItemPair(
            items: &discovery,
            hiddenControlItemWindowID: windowIDs.hidden,
            alwaysHiddenControlItemWindowID: windowIDs.alwaysHidden
        )
    }
}
