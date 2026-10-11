//
//  LayoutEditorModel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel
import SwiftUI

/// What the reorder editor shows, and what a drop in it does.
@MainActor
@Observable
final class LayoutEditorModel {
    typealias Unit = LayoutEditorOrder.Unit
    typealias Commit = @MainActor (LayoutDropCommit.Drop, UndoManager?, @escaping @MainActor () -> Void) -> Void

    /// How long a dropped order is shown before the editor goes back to what the menu bar reports.
    static let authoredOrderLimit = Duration.seconds(8)

    private(set) var units = [MenuBarSection.Name: [Unit]]()
    private(set) var itemsByID = [String: MenuBarItem]()

    @ObservationIgnored private let appState: AppState
    @ObservationIgnored private let commit: Commit
    @ObservationIgnored private var authored = [MenuBarSection.Name: (order: [String], since: ContinuousClock.Instant)]()
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var layoutChanges: AnyCancellable?

    init(appState: AppState, commit: Commit? = nil) {
        self.appState = appState
        self.commit = commit ?? { drop, undoManager, finished in
            LayoutDropCommit.commit(drop, appState: appState, undoManager: undoManager, finished: finished)
        }
    }

    var sections: [MenuBarSection.Name] {
        MenuBarSection.Name.allCases.filter { appState.menuBarManager.section(withName: $0)?.isEnabled == true }
    }

    func start() {
        guard observation == nil else { return }
        refresh()
        observation = Task { @MainActor [weak self, appState] in
            let changes = Observations {
                (
                    appState.itemManager.itemCache,
                    appState.itemManager.thawBarOnlyIdentifiers,
                    appState.itemGroupManager.groupSet,
                    appState.settings.advanced.enableAlwaysHiddenSection,
                    appState.settings.general.showThawIcon
                )
            }
            for await _ in changes {
                self?.refresh()
            }
        }
        // @Published emits before the property changes, so read on the next run-loop turn.
        layoutChanges = appState.menuBarManager.sectionLayoutChanges
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
    }

    func stop() {
        observation?.cancel()
        observation = nil
        layoutChanges = nil
    }

    func items(of unit: Unit) -> [MenuBarItem] {
        unit.memberIDs.compactMap { itemsByID[$0] }
    }

    func refresh() {
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let now = ContinuousClock.now
        var units = [MenuBarSection.Name: [Unit]]()
        var itemsByID = [String: MenuBarItem]()
        for section in sections {
            var items = LayoutDisplayedItems.items(in: section, appState: appState, runningApplications: running)
                .filter(LayoutBarPaddingView.acceptsLayoutDrag(of:))
            // The same item can be read twice: the leftmost one is shown, as in the Layout bars.
            var seen = Set<String>()
            items.removeAll { !seen.insert($0.uniqueIdentifier).inserted }
            if let held = authored[section] {
                let live = items.map(\.uniqueIdentifier)
                if LayoutEditorOrder.keepsAuthoredOrder(
                    authored: held.order,
                    live: live,
                    elapsed: now - held.since,
                    limit: Self.authoredOrderLimit
                ) {
                    let rank = Dictionary(uniqueKeysWithValues: held.order.enumerated().map { ($1, $0) })
                    items.sort { (rank[$0.uniqueIdentifier] ?? 0) < (rank[$1.uniqueIdentifier] ?? 0) }
                } else {
                    authored[section] = nil
                }
            }
            for item in items {
                itemsByID[item.uniqueIdentifier] = item
            }
            let groups = appState.itemGroupManager.resolvedGroups(for: items).map {
                (id: $0.origin.description, memberIndices: $0.memberIndices)
            }
            units[section] = LayoutEditorOrder.units(itemIDs: items.map(\.uniqueIdentifier), groups: groups)
        }
        // An unchanged read must not rebuild the rows: that can land in the middle of a drag.
        if self.units != units {
            self.units = units
        }
        if self.itemsByID != itemsByID {
            self.itemsByID = itemsByID
        }
    }

    func drop(_ difference: ReorderDifference<String, MenuBarSection.Name>, undoManager: UndoManager?) {
        guard let unitID = difference.sources.first else { return }
        let beforeID: String? = if case let .before(id) = difference.destination.position { id } else { nil }
        move(unitID, to: difference.destination.collectionID, before: beforeID, undoManager: undoManager)
    }

    /// Moves a unit to sit before another one in the target section, or at its end when `beforeID` is nil.
    func move(_ unitID: String, to target: MenuBarSection.Name, before beforeID: String?, undoManager: UndoManager?) {
        guard let change = LayoutEditorOrder.change(moving: unitID, in: units, to: target, before: beforeID) else {
            return
        }
        let previousTargetOrder = (units[target] ?? []).flatMap(items(of:))
        let drop = LayoutDropCommit.Drop(
            items: change.movedIDs.compactMap { itemsByID[$0] },
            source: change.source,
            target: target,
            previousTargetOrder: previousTargetOrder,
            targetOrder: change.itemIDs(in: target).compactMap { itemsByID[$0] }
        )
        guard drop.items.count == change.movedIDs.count,
              !LayoutDropCommit.refuses(drop, appState: appState)
        else {
            return
        }
        units = change.units
        // A group crossing sections lands in the target's stored order, so nothing is held for it.
        if change.source == target || drop.items.count == 1 {
            authored[target] = (change.itemIDs(in: target), .now)
        }
        commit(drop, undoManager) { [weak self] in
            self?.refresh()
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.authoredOrderLimit)
            self?.refresh()
        }
    }
}
