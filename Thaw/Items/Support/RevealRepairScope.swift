//
//  RevealRepairScope.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// What a repair that runs while a hidden section is revealed looks at, and when it stays out of the way.
///
/// The structural sync after a reveal, the boundary reconcile and the authored-order apply all start from
/// the same two refusals and pick the sections to work on from the section that was revealed. The caller
/// reads the live state and passes plain values in.
nonisolated enum RevealRepairScope {
    /// Why a reveal repair does nothing.
    enum Skip: Equatable {
        /// Manual arrangement owns the order, so a reveal shows items where the user last dragged them and
        /// automatic reordering is what the user declined.
        case manualArrangement
        /// A re-seat during or right after a ⌘-drag undoes the drop before its sections are read.
        case userArranging

        /// The end of the log line, after "skipping, ".
        var logReason: String {
            switch self {
            case .manualArrangement: "manual arrangement is on"
            case .userArranging: "the user is arranging the menu bar"
            }
        }
    }

    /// The first reason to stay out of the way, or nil when the repair may run.
    static func firstSkip(arrangementIsManual: Bool, isUserArranging: Bool) -> Skip? {
        if arrangementIsManual {
            return .manualArrangement
        }
        if isUserArranging {
            return .userArranging
        }
        return nil
    }

    /// The sections whose order a reveal puts right: the one revealed and the Hidden section above it.
    /// Visible is added when an edit to its order is still waiting to be applied to the bar, because
    /// without it an item moved into Visible keeps its old hidden-side slot for the whole reveal.
    static func sectionsToOrder(
        revealing revealedSection: MenuBarSection.Name,
        includeVisible: Bool = false
    ) -> [MenuBarSection.Name] {
        var sections: [MenuBarSection.Name] = switch revealedSection {
        case .visible, .hidden: [.hidden]
        case .alwaysHidden: [.hidden, .alwaysHidden]
        }
        if includeVisible {
            sections.append(.visible)
        }
        return sections
    }

    /// The sections a boundary reconcile checks assignments for. Visible is included: an item re-allowed
    /// at a hidden-side slot with no weight of its own is moved back nowhere else.
    static func sectionsToReconcile(revealing revealedSection: MenuBarSection.Name) -> Set<MenuBarSection.Name> {
        switch revealedSection {
        case .visible, .hidden: [.hidden, .visible]
        case .alwaysHidden: [.hidden, .alwaysHidden, .visible]
        }
    }

    /// Whether a section's authored order has to be applied to the bar. One item has no order to
    /// disagree about, and a section whose order macOS decides is left to it. Both reads of the bar are
    /// closures, asked in that order and only when the cheaper answers did not settle it.
    static func authoredOrderNeedsApply(
        authoredCount: Int,
        leavesOrderToMacOS: () -> Bool,
        liveOrderMatches: () -> Bool
    ) -> Bool {
        authoredCount > 1 && !leavesOrderToMacOS() && !liveOrderMatches()
    }
}
