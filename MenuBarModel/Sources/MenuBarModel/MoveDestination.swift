//
//  MoveDestination.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Lives here so the kit's backends can use it without the app's
/// MenuBarItemManager, which typealiases it.
public enum MoveDestination: Equatable, Sendable {
    case leftOfItem(MenuBarItem)
    case rightOfItem(MenuBarItem)

    public var targetItem: MenuBarItem {
        switch self {
        case let .leftOfItem(item), let .rightOfItem(item): item
        }
    }

    /// Whether the destination is to the right of the anchor, used for
    /// computing offset weights in cursor-free reorder.
    public var isRightward: Bool {
        if case .rightOfItem = self {
            return true
        }
        return false
    }

    /// The section reached across a control-item boundary, excluding a move
    /// relative to the mover itself and targets that are ordinary items.
    public func sectionAcrossBoundary(from movedItem: MenuBarItem) -> MenuBarSectionName? {
        let target = targetItem
        guard !movedItem.tag.matchesIgnoringWindowID(target.tag) else { return nil }
        if target.tag.matchesHiddenControlItem {
            return isRightward ? .visible : .hidden
        }
        if target.tag.matchesSectionBoundaryControlItem {
            return isRightward ? .hidden : .alwaysHidden
        }
        if target.tag.matchesVisibleControlItem {
            return isRightward ? nil : .visible
        }
        return nil
    }

    public var logString: String {
        switch self {
        case let .leftOfItem(item): "left of \(item.logString)"
        case let .rightOfItem(item): "right of \(item.logString)"
        }
    }
}
