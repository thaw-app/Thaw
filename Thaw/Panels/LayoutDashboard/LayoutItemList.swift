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
        return LayoutItemListRow(id: item.uniqueIdentifier, item: item, name: name, ownerName: shownOwner(for: item))
    }

    /// The owning app when it adds something: Apple's items name internal processes
    /// such as MenuBarAgent, which mean nothing to a person, so they show none.
    static func shownOwner(for item: MenuBarItem) -> String? {
        guard case let .string(bundleID) = item.tag.namespace, !bundleID.hasPrefix("com.apple.") else {
            return nil
        }
        return MenuBarItemDisplayName.subtitle(for: item)
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
    static let listMinWidth: CGFloat = 340
    static let listIdealWidth: CGFloat = 480
    static let editorMinWidth: CGFloat = 360
    static let editorIdealWidth: CGFloat = 380
    static let editorMaxWidth: CGFloat = 420
    /// The bars span the window, so the window is as wide as the list and the editor below them.
    static let windowMinSize = NSSize(width: listMinWidth + editorMinWidth + 48, height: barsHeight(sections: 3) + 340)
    /// The bars' pane fits its sections: each is a heading and a bar, plus the hint,
    /// the form's insets and the toolbar the content runs under.
    static func barsHeight(sections: Int) -> CGFloat {
        CGFloat(max(sections, 1)) * 80 + 90
    }

    /// A Finder-sidebar row, still a comfortable click target.
    static let rowHeight: CGFloat = 28
    /// Wide pictures such as the clock scale down into it, so names line up.
    static let pictureColumnWidth: CGFloat = 44
    static let checkboxColumnWidth: CGFloat = 18
}
