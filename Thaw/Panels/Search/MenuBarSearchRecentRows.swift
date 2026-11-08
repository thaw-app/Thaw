//
//  MenuBarSearchRecentRows.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

extension SectionedListItem where ID == MenuBarSearchModel.ItemID, Content == MenuBarSearchListContent {
    /// The recent rows under their heading, then the rest without them: an
    /// item listed twice shares one row ID, which stalls the arrows on it.
    /// restHeader names the rest when there are recents above it.
    static func recentsAbove(_ recentRows: [Self], _ rest: [Self], restHeader: Self?) -> [Self] {
        guard !recentRows.isEmpty else {
            return rest
        }
        let recentIDs = Set(recentRows.map(\.id))
        let remaining = rest.filter { !recentIDs.contains($0.id) }
        return [recentsHeader] + recentRows + (restHeader.map { [$0] } ?? []) + remaining
    }

    static var recentsHeader: Self {
        Self(content: .label(String(localized: "Recent")), id: .recentsHeader, isSelectable: false)
    }

    /// Heads the launchers' full list below the recents.
    static var allItemsHeader: Self {
        Self(content: .label(String(localized: "Menu Bar")), id: .allItemsHeader, isSelectable: false)
    }
}
