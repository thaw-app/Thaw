//
//  LayoutItemList.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import Ifrit
import MenuBarModel

/// One item in the Layout window's list.
struct LayoutItemListRow: Identifiable, Equatable {
    let id: String
    let item: MenuBarItem
    let name: String
    /// The owning app, when it says something the name doesn't.
    let ownerName: String?
    let section: MenuBarSectionName

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.ownerName == rhs.ownerName && lhs.section == rhs.section
    }
}

/// One section's rows in the order its bar shows them, or, with a query, every match ranked as search ranks it.
struct LayoutItemListSection: Identifiable, Equatable {
    /// Nil for the ranked matches, which have no heading.
    let name: MenuBarSectionName?
    let rows: [LayoutItemListRow]

    var id: String {
        name?.rawValue ?? "matches"
    }
}

/// Which sections the list shows.
enum LayoutItemListScope: String, CaseIterable, Hashable {
    case all, visible, hidden, alwaysHidden

    var section: MenuBarSectionName? {
        switch self {
        case .all: nil
        case .visible: .visible
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .all: "All"
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always Hidden"
        }
    }

    /// All, then each enabled section.
    static func offered(enabled: [MenuBarSectionName]) -> [Self] {
        allCases.filter { $0.section.map(enabled.contains) ?? true }
    }
}

/// The rows the Layout window lists: the items a drag in the bars can pick up, each once.
@MainActor
enum LayoutItemList {
    /// Search's own matcher, so a query finds the same items in both.
    private static let fuse = Fuse(threshold: 0.5)

    /// The enabled sections' rows from the same source the bars read.
    static func sections(appState: AppState, query: String, scope: LayoutItemListScope = .all) -> [LayoutItemListSection] {
        sections(from: items(appState: appState), order: enabledSections(appState: appState), query: query, scope: scope)
    }

    /// The sections that are switched on, in the bars' order.
    static func enabledSections(appState: AppState) -> [MenuBarSectionName] {
        MenuBarSectionName.allCases.filter { appState.menuBarManager.section(withName: $0)?.isEnabled == true }
    }

    /// Each enabled section's items, read from one projection of the item cache.
    static func items(appState: AppState) -> [MenuBarSectionName: [MenuBarItem]] {
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let inventory = DisplayedItemInventory.cache(appState: appState, runningApplications: running)
        return Dictionary(uniqueKeysWithValues: enabledSections(appState: appState).map { section in
            (section, LayoutDisplayedItems.editorItems(in: section, from: inventory, appState: appState))
        })
    }

    /// Without a query, the sections in order with their rows in bar order. With one, a single
    /// unheaded run of the matches, ranked by search's matcher and ranker. Scope keeps one section.
    static func sections(
        from items: [MenuBarSectionName: [MenuBarItem]],
        order: [MenuBarSectionName],
        query: String,
        scope: LayoutItemListScope = .all
    ) -> [LayoutItemListSection] {
        let shown = order.filter { scope.section == nil || scope.section == $0 }
        let names = MenuBarItemDisplayName.customNames()
        let row = { (item: MenuBarItem, section: MenuBarSectionName) in Self.row(item, in: section, customNames: names) }
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else {
            return shown.compactMap { section in
                let rows = (items[section] ?? []).map { row($0, section) }
                return rows.isEmpty ? nil : LayoutItemListSection(name: section, rows: rows)
            }
        }
        let rows = shown.flatMap { section in (items[section] ?? []).map { row($0, section) } }
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ranked = rankedIDs(matching: needle, in: rows).compactMap { byID[$0] }
        return ranked.isEmpty ? [] : [LayoutItemListSection(name: nil, rows: ranked)]
    }

    /// The last ranking, reused while the query and the rows are the same: matching costs
    /// tens of milliseconds at 165 items, and the list redraws more often than either changes.
    private static var lastRanking: (key: [String], ids: [String])?

    private static func rankedIDs(matching needle: String, in rows: [LayoutItemListRow]) -> [String] {
        let key = [needle] + rows.map { "\($0.id)\u{1F}\($0.name)" }
        if let lastRanking, lastRanking.key == key {
            return lastRanking.ids
        }
        let candidates = rows.map { row in
            PaletteCandidate(
                item: row.item,
                displayName: row.name,
                ownerName: MenuBarItemDisplayName.ownerName(for: row.item) ?? "",
                identityKey: row.id
            )
        }
        let ids = PaletteCandidate.ranked(matching: needle, in: candidates, using: fuse).map(\.identityKey)
        lastRanking = (key, ids)
        return ids
    }

    private static func row(_ item: MenuBarItem, in section: MenuBarSectionName, customNames: [String: String]) -> LayoutItemListRow {
        let name = MenuBarItemDisplayName.displayName(for: item, customNames: customNames)
        return LayoutItemListRow(id: item.uniqueIdentifier, item: item, name: name, ownerName: shownOwner(for: item, name: name), section: section)
    }

    /// The owning app when it adds something: Apple's items name internal processes
    /// such as MenuBarAgent, which mean nothing to a person, so they show none.
    static func shownOwner(for item: MenuBarItem, name: String) -> String? {
        guard case let .string(bundleID) = item.tag.namespace, !bundleID.hasPrefix("com.apple."), let owner = MenuBarItemDisplayName.ownerName(for: item), owner != name
        else {
            return nil
        }
        return owner
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
    /// The list is a sidebar; the editor takes the rest of the window.
    static let listMinWidth: CGFloat = 380
    static let listIdealWidth: CGFloat = 460
    static let listMaxWidth: CGFloat = 600
    static let editorMinWidth: CGFloat = 440
    /// The bars span the window, so the window is as wide as the list and the editor below them.
    static let windowMinSize = NSSize(width: listMinWidth + editorMinWidth + 48, height: barsHeight(sections: 3) + 340)
    /// The bars' pane fits its sections: each is a heading and a bar, plus the hint,
    /// the form's insets and the toolbar the content runs under.
    static func barsHeight(sections: Int) -> CGFloat {
        CGFloat(max(sections, 1)) * 80 + 90
    }

    /// Large rows, so a long list of small menu bar pictures stays easy to read and click.
    static let rowHeight: CGFloat = 44
    /// Wide pictures such as the clock scale down into it, so names line up.
    static let pictureColumnWidth: CGFloat = 72
    /// A real menu bar's glyph height, larger than search's rows.
    static let pictureHeight: CGFloat = 22
    static let checkboxColumnWidth: CGFloat = 24
}
