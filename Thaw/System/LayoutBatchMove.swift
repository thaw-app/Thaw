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
        case .missingItem: "Provide at least one item=<id>"
        case .missingSection: "Provide section=visible, hidden or alwaysHidden"
        case let .unknownSection(value): "Unknown section \(value); use visible, hidden or alwaysHidden"
        case let .duplicateItem(id): "Item \(id) is listed more than once"
        case let .anchorIsMovedItem(id): "Item \(id) cannot be placed after itself"
        case let .sectionDisabled(section): "The \(section.rawValue) section is turned off"
        case let .unknownItem(id): "No item in Layout has the identifier \(id)"
        case let .controlItem(id): "Item \(id) is one of Thaw's own control items"
        case let .groupedItem(id): "Item \(id) belongs to a group, which moves as a whole in Layout"
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
        let isGrouped: Bool
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

/// A parsed thaw://move-item URL.
///
///     thaw://move-item?item=<id>[&item=<id>...]&section=<visible|hidden|alwaysHidden>[&after=<id>]
///
/// The items land in the order given, right after the after item as the Layout pane shows the
/// section from left to right, or at the section's right end when after is absent.
nonisolated struct LayoutBatchMove: Equatable, Sendable {
    let itemIDs: [String]
    let section: MenuBarSectionName
    let afterID: String?

    static func parse(_ url: URL) -> Result<Self, LayoutBatchMoveError> {
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let itemIDs = queryItems.filter { $0.name == "item" }.compactMap(\.value).filter { !$0.isEmpty }
        let sectionValue = queryItems.first { $0.name == "section" }?.value ?? ""
        let afterID = queryItems.first { $0.name == "after" }?.value.flatMap { $0.isEmpty ? nil : $0 }

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
        return .success(Self(itemIDs: itemIDs, section: section, afterID: afterID))
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
            if let refusal = refusal(for: entry, from: current) {
                return .failure(refusal)
            }
            if current != section, source == nil {
                source = current
            }
        }

        let moved = Set(itemIDs)
        var order = previous.map(\.id).filter { !moved.contains($0) }
        var index = order.endIndex
        if let afterID {
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

    /// The same rules a drop in the Layout pane follows, except that control items never move.
    private func refusal(for entry: LayoutBatchMoveSnapshot.Entry, from current: MenuBarSectionName) -> LayoutBatchMoveError? {
        if entry.isControlItem {
            return .controlItem(entry.id)
        }
        if entry.isGrouped {
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
    case refused(LayoutBatchMoveError)
}

extension LauncherURIPayload {
    struct ItemMove: Codable, Equatable, Sendable {
        var version = LauncherURIPayload.version
        let itemIds: [String]
        let section: String?
        let after: String?
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
        case let .refused(error): error.code
        }
        let payload = LauncherURIPayload.ItemMove(
            itemIds: command?.itemIDs ?? [],
            section: command?.section.rawValue,
            after: command?.afterID,
            outcome: code
        )
        guard case let .refused(error) = outcome else {
            return success(payload, operation: .moveItem, requestId: requestId)
        }
        return failure(code, details: error.details, payload: payload, operation: .moveItem, requestId: requestId)
    }
}
