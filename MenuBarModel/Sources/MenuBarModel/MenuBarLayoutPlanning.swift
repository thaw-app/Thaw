//
//  MenuBarLayoutPlanning.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// What to do when the always-hidden section is targeted but its control item
/// divider is absent, which is the case whenever that section is switched off.
public enum MissingAlwaysHiddenDividerPolicy: Sendable {
    /// Fall back to the hidden control item. Used by the reconcile path, which
    /// must always produce a destination.
    case fallbackToHidden
    /// Yield nil so the caller skips the move. Used by the plan path, which
    /// reads an absent divider as "no achievable boundary".
    case skip
}

/// Plans reachable destinations around fixed anchors from a supplied snapshot, without another AX walk or input posting.
/// Callers execute moves separately; layout and move paths depend on this contract rather than a specific engine.
public protocol MenuBarLayoutPlanning: Sendable {
    /// Excludes system anchors and Thaw controls from stored order; their rule-based placement cannot follow a saved sequence.
    func isEligibleForSectionOrder(_ item: MenuBarItem, section: MenuBarSectionName) -> Bool

    /// Whether the live order already places item where destination asks,
    /// making the move a no-op worth skipping.
    func liveOrderSatisfiesDestination(
        items: [MenuBarItem],
        item: MenuBarItem,
        destination: MoveDestination,
        experimentalSystemItemHiding: Bool
    ) -> Bool

    /// Splits desired order into reachable runs; planning across an anchor would strand the item.
    func achievableOrderSegments(
        items: [MenuBarItem],
        desiredOrder: [String],
        experimentalSystemItemHiding: Bool
    ) -> [[MenuBarItem]]

    /// Returns one improving move, or nil when none helps; each move invalidates geometry for the next.
    func nextAchievableOrderMove(
        items: [MenuBarItem],
        desiredOrder: [String],
        experimentalSystemItemHiding: Bool
    ) -> (item: MenuBarItem, destination: MoveDestination)?

    /// Where item can land to honour desiredOrder, or nil when the order
    /// asks for a position anchors put out of reach.
    func achievableDestination(
        items: [MenuBarItem],
        item: MenuBarItem,
        desiredOrder: [String],
        experimentalSystemItemHiding: Bool
    ) -> MoveDestination?

    /// The move that returns Thaw's visible control item to its saved slot, or
    /// nil when it already sits there.
    func visibleControlRestoreMove(
        items: [MenuBarItem],
        desiredOrder: [String],
        experimentalSystemItemHiding: Bool
    ) -> (item: MenuBarItem, destination: MoveDestination)?

    /// Boundary repair checks only the side of the dividers, not order within the section.
    func liveOrderSatisfiesSectionBoundary(
        items: [MenuBarItem],
        item: MenuBarItem,
        section: MenuBarSectionName,
        controlItems: ControlItemPair,
        experimentalSystemItemHiding: Bool
    ) -> Bool

    /// Uses the section's control item as its leading-boundary insertion point.
    func sectionBoundaryDestination(
        for section: MenuBarSectionName,
        controlItems: ControlItemPair,
        missingAlwaysHidden: MissingAlwaysHiddenDividerPolicy
    ) -> MoveDestination?

    /// The move that restores a divider the bar has drifted past, or nil when
    /// the dividers are already where the assignment says they should be.
    func dividerMoveDestination(
        items: [MenuBarItem],
        sectionAssignment: [String: MenuBarSectionName],
        controlItems: ControlItemPair,
        experimentalSystemItemHiding: Bool
    ) -> MoveDestination?

    /// The live order rendered for a log line.
    func orderDescription(_ items: [MenuBarItem]) -> String
}

public extension MenuBarLayoutPlanning {
    /// Boundary destination for the plan path, which skips rather than falls
    /// back when the always-hidden divider is missing.
    func sectionBoundaryDestination(
        for section: MenuBarSectionName,
        controlItems: ControlItemPair
    ) -> MoveDestination? {
        sectionBoundaryDestination(for: section, controlItems: controlItems, missingAlwaysHidden: .skip)
    }
}
