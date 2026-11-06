//
//  MenuBarItemTag+OverflowTitles.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

extension MenuBarItemTag {
    /// The overflow control's labels in every language MenuBarAgent ships.
    ///
    /// Every language rather than Thaw's own: the app can run in a language
    /// other than the one the system bar is drawn in.
    static let menuBarAgentOverflowTitles = overflowControlTitles(
        inStringTable: FileManager.default.contents(
            atPath: "/System/Library/CoreServices/MenuBarAgent.app/Contents/Resources/MenuBarCore.loctable"
        )
    )

    /// The overflow control's show and hide labels in every language of a
    /// MenuBarAgent string table, keyed language first.
    static func overflowControlTitles(inStringTable data: Data?) -> Set<String> {
        guard let data,
              let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [] }
        let keys = ["menuBar.showOverflowItemsAccessibilityLabel", "menuBar.hideOverflowItemsAccessibilityLabel"]
        return Set(table.values.flatMap { strings in
            keys.compactMap { (strings as? [String: Any])?[$0] as? String }
        })
    }
}
