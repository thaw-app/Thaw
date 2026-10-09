//
//  MoveTargeting.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import PlatformRuntimeKit

/// Where a move may aim on the live bar, and which items it may touch.
///
/// The anchor a drop named can quit or rotate its window before the move runs, a stuck item
/// needs a seated neighbour to aim at, and some items sit on the wrong side of a divider or
/// are pinned by macOS. These rules answer from the items alone.
nonisolated enum MoveTargeting {
    /// Resolves the destination against the live bar: the anchor, then the
    /// alternates captured at drop time, since the anchor can quit or rotate
    /// its window ID. The first one present wins, rewritten to the live item.
    ///
    /// Nil rather than a throw, since the store write addresses the anchor by
    /// key and only the drag needs a live frame.
    static func resolvedDestination(
        for destination: MoveDestination,
        fallbacks: [MoveDestination],
        item: MenuBarItem,
        among livePeers: [MenuBarItem]
    ) -> MoveDestination? {
        let chain = [destination] + fallbacks
        for (index, candidate) in chain.enumerated() {
            guard
                let liveAnchor = livePeers.first(where: {
                    !$0.isSystemClone && !$0.isNativeOverflowControl && $0.hasSameIdentity(as: candidate.targetItem)
                })
            else {
                continue
            }
            let resolved: MoveDestination = switch candidate {
            case .leftOfItem: .leftOfItem(liveAnchor)
            case .rightOfItem: .rightOfItem(liveAnchor)
            }
            if index > 0 {
                MenuBarItemManager.diagLog.warning(
                    "Anchor \(destination.targetItem.logString) vanished mid-drop; " +
                        "resolved \(item.logString) against alternate \(resolved.targetItem.logString)"
                )
            } else if resolved != destination {
                MenuBarItemManager.diagLog.debug(
                    "Anchor \(destination.targetItem.logString) rotated during rescan mid-drop; " +
                        "re-resolved against live geometry"
                )
            }
            return resolved
        }
        return nil
    }

    /// The divider side a boundary-crossing write targets for destination.
    static func crossingSide(of destination: MoveDestination) -> RuntimePositionStore.BoundarySide {
        switch destination {
        case .leftOfItem: return .leftOfDivider
        case .rightOfItem: return .rightOfDivider
        @unknown default: return .rightOfDivider
        }
    }

    /// Prefers the hidden control item. macOS 27 does not order the
    /// zero-length window of an empty Hidden section, so the fallback is the
    /// rightmost seated visible item other than the stuck one.
    static func recoveryAnchor(
        stuck: MenuBarItem,
        items: [MenuBarItem],
        hiddenControlItemWindowNumber: Int?,
        section: (MenuBarItem) -> MenuBarSection.Name?
    ) -> MenuBarItem? {
        if let hiddenControlItemWindowNumber,
           let windowID = CGWindowID(exactly: hiddenControlItemWindowNumber),
           let seated = items.first(where: { $0.windowID == windowID })
        {
            return seated
        }
        return items
            .filter { candidate in
                candidate.windowID != stuck.windowID
                    && candidate.tag != .hiddenControlItem
                    && candidate.tag != .alwaysHiddenControlItem
                    && section(candidate) == .visible
                    && candidate.bounds.minX >= 0
                    && candidate.bounds.width > 0
            }
            .max { $0.bounds.maxX < $1.bounds.maxX }
    }

    /// Live items on the wrong side of the hidden divider for their section.
    /// Items no move could fix never count.
    static func membersStrandedAcrossDivider(
        items: [MenuBarItem],
        controlItems: ControlItemPair,
        sectionFor: (MenuBarItem) -> MenuBarSection.Name,
        experimentalSystemItemHiding: Bool,
        isRepairSuppressed: (MenuBarItem) -> Bool = { _ in false }
    ) -> [MenuBarItem] {
        items.filter { item in
            guard !item.isControlItem, !item.isSystemClone, !item.isNativeOverflowControl else { return false }
            // An item the repair ladder has given up on cannot be moved by any
            // weight, so repairing it here only re-seats its neighbours, and it
            // strands again on the next reveal.
            guard !isRepairSuppressed(item) else { return false }
            return !MenuBarLayoutPlannerProvider.current.liveOrderSatisfiesSectionBoundary(
                items: items,
                item: item,
                section: sectionFor(item),
                controlItems: controlItems,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            )
        }
    }

    static func controlItemSectionName(for tag: MenuBarItemTag) -> MenuBarSection.Name? {
        switch tag {
        case .visibleControlItem: .visible
        case .hiddenControlItem: .hidden
        case .alwaysHiddenControlItem: .alwaysHidden
        default: nil
        }
    }

    /// Whether a persisted namespace:title identifier names an item macOS
    /// pins, mirroring MenuBarItemTag.isNonConcealableSystemItem for the
    /// case where only the identifier is in hand.
    static func namesPinnedSystemItem(_ identifier: String) -> Bool {
        identifier.hasPrefix("com.apple.")
    }
}
