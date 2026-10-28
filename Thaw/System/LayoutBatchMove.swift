//
//  LayoutBatchMove.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// Why a thaw://move-item request was refused. Each case names the item or value at fault.
nonisolated enum LayoutBatchMoveError: Error, Equatable, Sendable {
    case missingItem
    case missingSection
    case unknownSection(String)
    case duplicateItem(String)
    case anchorIsMovedItem(String)
    case sectionDisabled(MenuBarSectionName)
    case unknownItem(String)
    case controlItem(String)
    case groupedItem(String)
    case notMovable(String, MenuBarSectionName)
    case unknownAnchor(String)
    /// The plan was valid, but the move path declined it, for example because an item quit meanwhile.
    case moveRefused

    /// A stable code for the response's error field.
    var code: String {
        switch self {
        case .missingItem, .missingSection, .unknownSection, .duplicateItem, .anchorIsMovedItem:
            LauncherURIResponse.invalidRequest
        case .sectionDisabled: "sectionDisabled"
        case .unknownItem: "itemUnavailable"
        case .controlItem, .groupedItem, .notMovable: "itemNotMovable"
        case .unknownAnchor: "anchorUnavailable"
        case .moveRefused: "moveRefused"
        }
    }

    /// A readable explanation for logs and the response's details field.
    var details: String {
        switch self {
        case .missingItem: "Provide at least one item-id=<id>"
        case .missingSection: "Provide section=visible, hidden or alwaysHidden"
        case let .unknownSection(value): "Unknown section \(value); use visible, hidden or alwaysHidden"
        case let .duplicateItem(id): "Item \(id) is listed more than once"
        case let .anchorIsMovedItem(id): "Item \(id) cannot be placed after itself"
        case let .sectionDisabled(section): "The \(section.rawValue) section is turned off"
        case let .unknownItem(id): "No item in Layout has the identifier \(id)"
        case let .controlItem(id): "Item \(id) is one of Thaw's own control items"
        case let .groupedItem(id): "Item \(id) belongs to a group; list every member to move the group as a whole"
        case let .notMovable(id, section): "Item \(id) cannot move to \(section.rawValue)"
        case let .unknownAnchor(id): "No item in the target section has the identifier \(id)"
        case .moveRefused: "The move path declined the move; an item may have quit or could not be assigned"
        }
    }
}

/// What the Layout pane shows, reduced to what a move request is checked against.
nonisolated struct LayoutBatchMoveSnapshot: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let id: String
        let isControlItem: Bool
        /// The group the item belongs to in Layout, nil when it is in none.
        let groupID: String?
        /// The sections the item may be assigned to.
        let assignableSections: Set<MenuBarSectionName>
        /// Whether the item can change place inside Visible.
        let reordersInVisible: Bool
    }

    /// Each enabled section's items, left to right as the Layout pane shows them.
    let sections: [MenuBarSectionName: [Entry]]

    func section(of id: String) -> MenuBarSectionName? {
        MenuBarSectionName.allCases.first { sections[$0]?.contains { $0.id == id } == true }
    }

    func entry(_ id: String) -> Entry? {
        sections.values.lazy.flatMap(\.self).first { $0.id == id }
    }

    /// Every member of the group, in all sections.
    func members(ofGroup groupID: String) -> [String] {
        sections.values.flatMap(\.self).filter { $0.groupID == groupID }.map(\.id)
    }
}

/// One move of one or more items, worked out before anything is written.
nonisolated struct LayoutBatchMovePlan: Equatable, Sendable {
    /// The moved items in the order the request gave them.
    let itemIDs: [String]
    /// The section the first item that changes section comes from, or the target when none does.
    let source: MenuBarSectionName
    let target: MenuBarSectionName
    let previousTargetOrder: [String]
    let targetOrder: [String]

    /// Whether the move leaves every item where it already is.
    var changesNothing: Bool {
        source == target && previousTargetOrder == targetOrder
    }
}

/// A move of one or more items, parsed from a thaw://move-item URL or made by the Layout pane.
///
///     thaw://move-item?item-id=<id>[&item-id=<id>...]&section=<visible|hidden|alwaysHidden>[&after-id=<id>]
///
/// The items land in the order given, right after the after-id item as the Layout pane shows the
/// section from left to right, or at the section's right end when after-id is absent.
nonisolated struct LayoutBatchMove: Equatable, Sendable {
    /// Where the items land in the target section, read left to right.
    enum Placement: Equatable, Sendable {
        case start
        case end
        case after(String)
    }

    let itemIDs: [String]
    let section: MenuBarSectionName
    let placement: Placement

    /// The anchor item, when the items land right after one.
    var afterID: String? {
        if case let .after(id) = placement { id } else { nil }
    }

    static func parse(_ url: URL) -> Result<Self, LayoutBatchMoveError> {
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return parse(SettingsURIMoveQuery(queryItems: queryItems))
    }

    static func parse(_ query: SettingsURIMoveQuery) -> Result<Self, LayoutBatchMoveError> {
        let itemIDs = query.itemIDs
        let sectionValue = query.section
        let afterID = query.afterID

        guard !itemIDs.isEmpty else { return .failure(.missingItem) }
        guard !sectionValue.isEmpty else { return .failure(.missingSection) }
        guard let section = MenuBarSectionName.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(sectionValue) == .orderedSame
        }) else {
            return .failure(.unknownSection(sectionValue))
        }
        var seen = Set<String>()
        if let duplicate = itemIDs.first(where: { !seen.insert($0).inserted }) {
            return .failure(.duplicateItem(duplicate))
        }
        if let afterID, itemIDs.contains(afterID) {
            return .failure(.anchorIsMovedItem(afterID))
        }
        return .success(Self(itemIDs: itemIDs, section: section, placement: afterID.map(Placement.after) ?? .end))
    }

    /// Checks every item against the snapshot first, then works out the target order.
    /// The first item that cannot move refuses the whole request.
    func plan(in snapshot: LayoutBatchMoveSnapshot) -> Result<LayoutBatchMovePlan, LayoutBatchMoveError> {
        guard let previous = snapshot.sections[section] else {
            return .failure(.sectionDisabled(section))
        }
        var source: MenuBarSectionName?
        for id in itemIDs {
            guard let entry = snapshot.entry(id), let current = snapshot.section(of: id) else {
                return .failure(.unknownItem(id))
            }
            if let refusal = refusal(for: entry, from: current, in: snapshot) {
                return .failure(refusal)
            }
            if current != section, source == nil {
                source = current
            }
        }

        let moved = Set(itemIDs)
        var order = previous.map(\.id).filter { !moved.contains($0) }
        let index: Int
        switch placement {
        case .start:
            index = order.startIndex
        case .end:
            index = order.endIndex
        case let .after(afterID):
            guard let anchor = order.firstIndex(of: afterID) else {
                return .failure(.unknownAnchor(afterID))
            }
            index = order.index(after: anchor)
        }
        order.insert(contentsOf: itemIDs, at: index)
        return .success(LayoutBatchMovePlan(
            itemIDs: itemIDs,
            source: source ?? section,
            target: section,
            previousTargetOrder: previous.map(\.id),
            targetOrder: order
        ))
    }

    /// A Layout drop's rules, except that control items never move and a group moves only whole.
    private func refusal(
        for entry: LayoutBatchMoveSnapshot.Entry,
        from current: MenuBarSectionName,
        in snapshot: LayoutBatchMoveSnapshot
    ) -> LayoutBatchMoveError? {
        if entry.isControlItem {
            return .controlItem(entry.id)
        }
        if let groupID = entry.groupID, !Set(itemIDs).isSuperset(of: snapshot.members(ofGroup: groupID)) {
            return .groupedItem(entry.id)
        }
        let movable = current == section
            ? section != .visible || entry.reordersInVisible
            : entry.assignableSections.contains(section)
        return movable ? nil : .notMovable(entry.id, section)
    }
}

/// What became of thaw://move-item.
nonisolated enum LayoutBatchMoveOutcome: Equatable, Sendable {
    case moved(LayoutBatchMovePlan)
    case unchanged(LayoutBatchMovePlan)
    /// The order was saved but the bar did not follow within the wait.
    case notApplied(LayoutBatchMovePlan)
    case refused(LayoutBatchMoveError)
}

extension LauncherURIPayload {
    struct ItemMove: Codable, Equatable, Sendable {
        var version = LauncherURIPayload.version
        let itemIds: [String]
        let section: String?
        let afterId: String?
        let outcome: String
    }
}

extension LauncherURIResponse {
    static func itemMove(
        _ outcome: LayoutBatchMoveOutcome,
        command: LayoutBatchMove?,
        requestId: String
    ) -> [String: Any] {
        let code: String = switch outcome {
        case .moved: "moved"
        case .unchanged: "unchanged"
        case .notApplied: "notApplied"
        case let .refused(error): error.code
        }
        let payload = LauncherURIPayload.ItemMove(
            itemIds: command?.itemIDs ?? [],
            section: command?.section.rawValue,
            afterId: command?.afterID,
            outcome: code
        )
        let details: String
        switch outcome {
        case let .refused(error):
            details = error.details
        case .notApplied:
            details = "The new order was saved, but the menu bar did not follow it. Check the bar and retry."
        case .moved, .unchanged:
            return success(payload, operation: .moveItem, requestId: requestId)
        }
        return failure(code, details: details, payload: payload, operation: .moveItem, requestId: requestId)
    }
}
