//
//  VisibleOrderCompletion.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Completes a saved Visible order with the live Visible items it does not name, before the kit plans a write.
@MainActor
enum VisibleOrderCompletion {
    /// The live items the kit puts in a Visible segment, in bar order: orderable eligible Visible
    /// items, and Thaw's own Visible control, which the kit segments although it is not eligible.
    static func liveVisibleIdentifiers(
        in items: [MenuBarItem],
        controller: any MenuBarSectionControlling,
        experimentalSystemItemHiding: Bool
    ) -> [String] {
        items
            .filter {
                $0.isPhysicallyOrderable(experimentalSystemItemHiding: experimentalSystemItemHiding) &&
                    ($0.tag.matchesVisibleControlItem ||
                        (MenuBarLayoutPlannerProvider.current.isEligibleForSectionOrder($0, section: .visible) &&
                            controller.section(for: $0) == .visible))
            }
            .map(\.uniqueIdentifier)
    }

    /// The order with every live Visible item named; unchanged when none is missing.
    static func completed(
        _ order: [String],
        liveItems: [MenuBarItem],
        controller: any MenuBarSectionControlling,
        experimentalSystemItemHiding: Bool
    ) -> [String] {
        LayoutEditorOrder.completingOrder(
            order,
            withLive: liveVisibleIdentifiers(
                in: liveItems,
                controller: controller,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            )
        )
    }
}
