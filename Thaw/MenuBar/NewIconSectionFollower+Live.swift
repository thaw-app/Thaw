//
//  NewIconSectionFollower+Live.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Observation

/// Applies NewIconArrivals as the item cache changes.
@MainActor
final class NewIconSectionFollower {
    private static let diagLog = DiagLog(category: "NewIconSectionFollower")
    private var task: Task<Void, Never>?

    func start(appState: AppState) {
        task?.cancel()
        task = Task { @MainActor [weak appState] in
            guard let itemManager = appState?.itemManager else { return }
            var arrivals: NewIconArrivals?
            let changes = Observations { Self.itemIdentifiers(in: itemManager) }
            for await current in changes {
                guard let appState else { return }
                let controller = appState.menuBarManager.sectionController
                let saved = Array(controller.sectionItemOrder.values.joined())
                // The first read only says what is already there.
                guard arrivals != nil else {
                    arrivals = NewIconArrivals(seen: itemManager.knownItemIdentifiers.union(saved).union(current))
                    continue
                }
                let placements = arrivals?.placements(
                    current: current,
                    saved: saved,
                    authored: controller.authoredSection(for:),
                    newItemsSection: itemManager.effectiveNewItemsSection
                ) ?? []
                for placement in placements {
                    Self.diagLog.info("\(placement.identifier) is new; placing it in \(placement.section)")
                    appState.menuBarManager.assignSection(placement.section, identifier: placement.identifier)
                    if placement.isNewApp {
                        Self.moveToNewItemsSlot(placement, itemManager: itemManager, controller: controller)
                    }
                }
            }
        }
    }

    /// Puts a new app's icon where Layout shows the New Items placeholder, next to its anchor item.
    /// Manual arrangement keeps the slot in the saved order but leaves the bar as it is.
    private static func moveToNewItemsSlot(
        _ placement: NewIconArrivals.Placement,
        itemManager: MenuBarItemManager,
        controller: any MenuBarSectionControlling
    ) {
        let section = placement.section
        let others = NewIconArrivals.others(than: placement.identifier, in: controller.sectionItemOrder[section] ?? [])
        guard let index = itemManager.newItemsBadgeIndex(in: section, itemIdentifiers: others) else { return }
        controller.setSectionOrder(NewIconArrivals.order(placing: placement.identifier, among: others, at: index), for: section)
        itemManager.scheduleSectionOrderApply(for: section)
        diagLog.info("\(placement.identifier) takes the New Items slot \(index) in \(section)")
    }

    private static func itemIdentifiers(in itemManager: MenuBarItemManager) -> [String] {
        itemManager.managedItems.filter { !$0.isControlItem }.map(\.uniqueIdentifier)
    }
}
