//
//  PostRestrictionUnpark.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

/// The post-restriction repair's unpark decisions: the item a parked visible item is dropped beside, the
/// neighbours the drop falls back on, and what a failed drop says about the item.
///
/// The caller reads the bar, the screens and the settings, and keeps the moves, the records and the logging.
nonisolated enum PostRestrictionUnpark {
    /// The item parked visible items are dropped to the left of: the visible control item while it is on the
    /// bar, otherwise the rightmost Visible item on the bar that is not a control item.
    static func anchor(
        among liveItems: [MenuBarItem],
        screens: [CGRect],
        sectionOf: (MenuBarItem) -> MenuBarSectionName
    ) -> MenuBarItem? {
        let onBand = liveItems.filter { !$0.isParkedOffMenuBarBand(among: liveItems, screens: screens) }
        if let control = onBand.first(where: { $0.tag.matchesVisibleControlItem }) {
            return control
        }
        return onBand
            .filter { !$0.isControlItem && sectionOf($0) == .visible }
            .max(by: { $0.bounds.midX < $1.bounds.midX })
    }

    /// The anchor's nearest orderable neighbours, left one first, taken from the same scan
    /// because a later scan may no longer be trustworthy.
    static func fallbacks(
        for anchor: MenuBarItem,
        among liveItems: [MenuBarItem],
        screens: [CGRect],
        experimentalSystemItemHiding: Bool
    ) -> [MoveDestination] {
        let ordered = MenuBarItem.sortByLeadingEdge(
            liveItems.filter {
                !$0.isSystemClone &&
                    !$0.isNativeOverflowControl &&
                    !$0.isControlItem &&
                    $0.bounds.width > 0 &&
                    !$0.isParkedOffMenuBarBand(among: liveItems, screens: screens)
            }
        )
        guard let anchorIndex = ordered.firstIndex(where: {
            $0.uniqueIdentifier == anchor.uniqueIdentifier
        }) else {
            return []
        }

        var chain = [MoveDestination]()
        if let left = ordered[..<anchorIndex].last(where: {
            $0.isPhysicallyOrderable(experimentalSystemItemHiding: experimentalSystemItemHiding)
        }) {
            chain.append(.rightOfItem(left))
        }
        if anchorIndex + 1 < ordered.count,
           let right = ordered[(anchorIndex + 1)...].first(where: {
               $0.isPhysicallyOrderable(experimentalSystemItemHiding: experimentalSystemItemHiding)
           })
        {
            chain.append(.leftOfItem(right))
        }
        return chain
    }

    /// What a failed unpark says about the item.
    enum Failure: Equatable {
        /// The pass was cancelled and stops.
        case cancelled
        /// Every anchor vanished mid-drop, which says nothing about the item.
        case anchorsLost
        /// The item moves only with system item hiding on, a gate the user can lift in Settings.
        case awaitsExperimentalHiding
        /// The item refused the move, with the refusal when one was known.
        case notMovable(MenuBarItem.OrderabilityRefusal?)
        /// The move could not complete.
        case cannotComplete
        /// Any other error. A one-off error may not mean the item is unmovable.
        case other

        /// The kind the failure ledger is told, or nil when the failure is not recorded, so that it
        /// cannot become a "won't move" verdict that outlives a relaunch.
        var ledgerKind: MenuBarItemFailureLedger.FailureKind? {
            switch self {
            case .cancelled, .anchorsLost, .awaitsExperimentalHiding:
                nil
            case .notMovable, .cannotComplete:
                .cannotComplete
            case .other:
                .other
            }
        }
    }

    /// The failure an unpark error stands for.
    static func failure(for error: any Error) -> Failure {
        switch error {
        case is CancellationError:
            .cancelled
        case MenuBarItemManager.EventError.destinationAnchorLost:
            .anchorsLost
        case let MenuBarItemManager.EventError.itemNotMovable(_, refusal):
            refusal == .requiresExperimentalHiding ? .awaitsExperimentalHiding : .notMovable(refusal)
        case MenuBarItemManager.EventError.cannotComplete:
            .cannotComplete
        default:
            .other
        }
    }
}
