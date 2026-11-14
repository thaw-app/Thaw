//
//  MenuBarSearchModel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Ifrit
import MenuBarModel
import Observation
import SwiftUI
import ThawUI

/// One row of the search list: an item, the app that owns it when that says
/// something the item's name doesn't, and the heading it sits under.
struct MenuBarSearchResult: Identifiable {
    let item: MenuBarItem
    let ownerName: String?
    /// The heading over this row, or nil for ranked matches, which have none.
    let section: String?

    var id: MenuBarSearchModel.ItemID {
        MenuBarSearchModel.ItemID(item)
    }

    /// Where a row sits, for telling a move from a new query.
    struct Placement: Equatable {
        let id: MenuBarSearchModel.ItemID
        let section: String?
    }

    var placement: Placement {
        Placement(id: id, section: section)
    }
}

/// The search panel's state, as Floe's menu bar search keeps it: the query,
/// the results, the highlighted row and the rename in progress.
@MainActor
@Observable
final class MenuBarSearchModel {
    /// Identifies an item's row. The window ID tells two items with one tag apart.
    struct ItemID: Hashable {
        let tag: MenuBarItemTag
        let windowID: CGWindowID?

        init(tag: MenuBarItemTag, windowID: CGWindowID?) {
            self.tag = tag
            self.windowID = windowID
        }

        init(_ item: MenuBarItem) {
            self.init(tag: item.tag, windowID: item.windowID)
        }
    }

    /// Text currently typed into the search field.
    var searchText = ""

    /// What the list shows for searchText.
    var results = [MenuBarSearchResult]()

    /// The highlighted row, if there is one.
    var selection: ItemID?

    /// An inline rename in progress. Bundling the target and the draft into
    /// one value means a draft can never outlive the row it belongs to.
    struct RenameSession: Equatable {
        /// Tag of the item being renamed.
        let tag: MenuBarItemTag

        /// Window the rename was started from, when the row knew it. Lookups
        /// prefer this over the tag, which can be ambiguous.
        let windowID: CGWindowID?

        /// Text typed so far, not yet committed.
        var draft: String

        /// Whether this session is renaming item.
        func targets(_ item: MenuBarItem) -> Bool {
            tag == item.tag && windowID == item.windowID
        }
    }

    /// The rename in progress, or nil while nothing is being renamed.
    var renameSession: RenameSession?

    let fuse = Fuse(threshold: 0.5)

    /// Cached between keystrokes, since building one resolves each item's app.
    /// Emptied when the item cache turns over or a rename changes a name.
    @ObservationIgnored
    var candidates = [PaletteCandidate]()

    /// The custom names the cached candidates were built with, independent of inventory turnover.
    @ObservationIgnored
    private var candidateCustomNames = [String: String]()

    /// Recently opened items, listed on top while nothing is typed.
    @ObservationIgnored
    let recents: MenuBarSearchRecents

    /// The query the shown results answer, so a keystroke that reorders them isn't taken for a move.
    @ObservationIgnored
    private var resultsQuery = ""

    init(recents: MenuBarSearchRecents = MenuBarSearchRecents()) {
        self.recents = recents
    }

    // MARK: Results

    /// With nothing typed: recents, then each section's items in menu bar order.
    /// With a query: the ranked matches. The highlight stays while its row is listed.
    func refresh(from inventory: MenuBarItemCache, sections: [MenuBarSection.Name] = MenuBarSection.Name.allCases) {
        let customNames = MenuBarItemDisplayName.customNames()
        if candidates.isEmpty || customNames != candidateCustomNames {
            candidates = PaletteCandidate.inventory(from: inventory)
            candidateCustomNames = customNames
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let fresh = if query.isEmpty {
            Self.grouped(recents.resolve(in: inventory), in: inventory, sections: sections, candidates: candidates)
        } else {
            PaletteCandidate.ranked(matching: query, in: candidates, using: fuse).map {
                MenuBarSearchResult(item: $0.item, ownerName: $0.subtitle, section: nil)
            }
        }
        // A moved item slides to its new section; typing still swaps the list at once.
        let sameQuery = query == resultsQuery
        resultsQuery = query
        if Self.isRearrangement(from: results.map(\.placement), to: fresh.map(\.placement), sameQuery: sameQuery) {
            withThawAnimation(ThawMotion.settle) { results = fresh }
        } else {
            results = fresh
        }
        revalidateSelection()
        endRenameIfRowGone()
    }

    /// A rename whose row left the list has no field to type into, so it ends
    /// and the query field gets the keyboard back.
    private func endRenameIfRowGone() {
        guard let session = renameSession, !results.contains(where: { session.targets($0.item) }) else {
            return
        }
        renameSession = nil
    }

    /// Whether the same query brought back the same rows reordered or regrouped, as after a move.
    static func isRearrangement(
        from old: [MenuBarSearchResult.Placement],
        to new: [MenuBarSearchResult.Placement],
        sameQuery: Bool = true
    ) -> Bool {
        sameQuery && old != new && old.count == new.count && Set(old.map(\.id)) == Set(new.map(\.id))
    }

    /// Each item is listed once: a second row with the same ID stalls the arrows.
    /// Spacers and control items drop out. An item caught mid-move can still sit
    /// in two sections of the cache, so one already listed is skipped.
    static func grouped(
        _ recentItems: [MenuBarItem],
        in inventory: MenuBarItemCache,
        sections: [MenuBarSection.Name],
        candidates: [PaletteCandidate]
    ) -> [MenuBarSearchResult] {
        let byIdentity = Dictionary(candidates.map { ($0.identityKey, $0) }, uniquingKeysWith: { first, _ in first })
        var listed = Set<String>()
        let recentTitle = String(localized: "Recent")
        let recent = recentItems.compactMap { byIdentity[$0.uniqueIdentifier] }
            .filter { listed.insert($0.identityKey).inserted }
        var results = recent.map { MenuBarSearchResult(item: $0.item, ownerName: $0.subtitle, section: recentTitle) }
        for name in sections {
            // The cache lists a section right to left.
            let items = inventory.managedItems(for: name).reversed()
                .compactMap { byIdentity[$0.uniqueIdentifier] }
                .filter { listed.insert($0.identityKey).inserted }
            results += items.map { MenuBarSearchResult(item: $0.item, ownerName: $0.subtitle, section: name.localizedName) }
        }
        return results
    }

    // MARK: Selection

    /// The highlighted row's position in results, if it is listed.
    var selectedIndex: Int? {
        results.firstIndex { $0.id == selection }
    }

    /// The highlighted row, if it is listed.
    var selectedResult: MenuBarSearchResult? {
        selectedIndex.map { results[$0] }
    }

    func selectFirstRow() {
        selection = results.first?.id
    }

    /// Moves the highlight to the first row once its own row is gone.
    func revalidateSelection() {
        if selectedIndex == nil {
            selectFirstRow()
        }
    }

    /// Tab's jump to the next or previous section's first row, wrapping.
    /// Ranked matches have no sections, so it does nothing then.
    func moveSelection(toSectionFromCurrentBy step: Int) {
        let starts = sectionStarts
        guard canJumpBetweenSections else {
            return
        }
        let index = selectedIndex ?? 0
        let current = starts.lastIndex { $0 <= index } ?? 0
        let target = (current + step % starts.count + starts.count) % starts.count
        selection = results[starts[target]].id
    }

    /// Each section's first row, in order: headings start where the section changes.
    private var sectionStarts: [Int] {
        results.indices.filter { $0 == 0 || results[$0].section != results[$0 - 1].section }
    }

    /// Whether the results have more than one titled section to jump between.
    var canJumpBetweenSections: Bool {
        results.first?.section != nil && sectionStarts.count > 1
    }

    /// Moves the highlight by delta rows, held to the rows there are. With no
    /// highlight, any move starts at the first row.
    func moveSelection(by delta: Int) {
        guard let index = selectedIndex else {
            selectFirstRow()
            return
        }
        let target = LauncherListStep.moved(index, by: delta, count: results.count)
        if target != index {
            selection = results[target].id
        }
    }
}
