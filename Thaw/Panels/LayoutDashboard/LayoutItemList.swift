//
//  LayoutItemList.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// One item in the Layout window's list.
struct LayoutItemListRow: Identifiable, Equatable {
    let id: String
    let item: MenuBarItem
    let name: String
    /// The owning app, when it says something the name doesn't.
    let ownerName: String?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.ownerName == rhs.ownerName
    }
}

/// One section's rows, in the order its bar shows them.
struct LayoutItemListSection: Identifiable, Equatable {
    let name: MenuBarSectionName
    let rows: [LayoutItemListRow]

    var id: MenuBarSectionName {
        name
    }
}

/// The rows the Layout window lists: the items a drag in the bars can pick up, each once.
@MainActor
enum LayoutItemList {
    /// The enabled sections' rows from the same source the bars read, filtered by query.
    static func sections(appState: AppState, query: String) -> [LayoutItemListSection] {
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let enabled = MenuBarSectionName.allCases.filter { appState.menuBarManager.section(withName: $0)?.isEnabled == true }
        let items = Dictionary(uniqueKeysWithValues: enabled.map { section in
            (section, LayoutDisplayedItems.editorItems(in: section, appState: appState, runningApplications: running))
        })
        return sections(from: items, order: enabled, query: query)
    }

    /// Rows per section in order, keeping those whose name or app matches query.
    static func sections(
        from items: [MenuBarSectionName: [MenuBarItem]],
        order: [MenuBarSectionName],
        query: String
    ) -> [LayoutItemListSection] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return order.compactMap { section in
            let rows = (items[section] ?? []).map(row).filter { matches($0, needle) }
            return rows.isEmpty ? nil : LayoutItemListSection(name: section, rows: rows)
        }
    }

    private static func row(_ item: MenuBarItem) -> LayoutItemListRow {
        let name = MenuBarItemDisplayName.displayName(for: item)
        let owner = MenuBarItemDisplayName.ownerName(for: item)
        return LayoutItemListRow(id: item.uniqueIdentifier, item: item, name: name, ownerName: owner == name ? nil : owner)
    }

    private static func matches(_ row: LayoutItemListRow, _ needle: String) -> Bool {
        needle.isEmpty
            || row.name.localizedCaseInsensitiveContains(needle)
            || (row.ownerName?.localizedCaseInsensitiveContains(needle) ?? false)
    }

    /// The row after or before current among rows, held to the ends; the first row when nothing is current.
    static func step(from current: String?, by delta: Int, in rows: [LayoutItemListRow]) -> LayoutItemListRow? {
        guard !rows.isEmpty else { return nil }
        guard let current, let index = rows.firstIndex(where: { $0.id == current }) else { return rows.first }
        return rows[max(0, min(index + delta, rows.count - 1))]
    }
}

/// The Layout window's measures, so the list and the bars both keep a usable width.
enum LayoutDashboardMetrics {
    static let listMinWidth: CGFloat = 300
    static let listIdealWidth: CGFloat = 380
    static let barsMinWidth: CGFloat = 560
    /// The list and the bars at their minimum, with room for the divider.
    static let windowMinSize = NSSize(width: listMinWidth + barsMinWidth + 40, height: 560)
}
