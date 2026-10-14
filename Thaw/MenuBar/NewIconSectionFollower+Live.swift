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
                    current: current, saved: saved, authored: controller.authoredSection(for:)
                ) ?? []
                for placement in placements {
                    Self.diagLog.info("\(placement.identifier) is new and its app is in \(placement.section); placing it there")
                    appState.menuBarManager.assignSection(placement.section, identifier: placement.identifier)
                }
            }
        }
    }

    private static func itemIdentifiers(in itemManager: MenuBarItemManager) -> [String] {
        itemManager.managedItems.filter { !$0.isControlItem }.map(\.uniqueIdentifier)
    }
}
