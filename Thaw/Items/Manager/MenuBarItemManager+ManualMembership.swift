//
//  MenuBarItemManager+ManualMembership.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

extension MenuBarItemManager {
    /// macOS writes positions after the drop; wait before reading the table.
    static let manualMembershipSettle = Duration.milliseconds(1500)

    /// Holds structural writes through post-drag settling, membership adoption, and a safety margin.
    static let userArrangementQuietPeriod = Duration.seconds(4)

    /// Suppresses reveal re-seats and boundary repairs during and just after ⌘-drag so they cannot undo the drop.
    var isUserArrangingMenuBar: Bool {
        if appState?.isDraggingMenuBarItem == true {
            return true
        }
        guard let lastUserMenuBarDragEnd else { return false }
        return lastUserMenuBarDragEnd.duration(to: .now) < Self.userArrangementQuietPeriod
    }

    /// The stored weights as a baseline for a ⌘-drag starting now; nil unless the dividers read in order.
    func dragStartReading() -> ObservedMembership.DragBaseline? {
        currentObservedMembership().flatMap { observed in
            guard case let .ordered(dividers) = observed.reading else { return nil }
            return ObservedMembership.DragBaseline(candidates: observed.candidates, dividers: dividers)
        }
    }

    /// Records the end of a ⌘-drag and reads the sections it produced.
    func noteUserMenuBarDragEnded() {
        lastUserMenuBarDragEnd = .now
        // Coalesced drags share one adoption, so the last drop's visibility is what counts.
        let alwaysHiddenShownAtDrop = appState?.menuBarManager.sectionController.revealedSection == .alwaysHidden
        scheduleObservedMembershipAdoption(
            reason: "⌘-drag",
            afterUserDrag: true,
            alwaysHiddenShownAtDrop: alwaysHiddenShownAtDrop
        )
    }

    /// Adopt divider-weight membership without moving items: Manual after drags, mode switches, and launch; Automatic only after user drags.
    /// Leave unweighted, unhideable, Thaw Bar Only, and divider-slot items unchanged.
    /// keepingAuthored only places items that have no section yet. After a drag, only items it carried across a divider move.
    func adoptObservedMembership(
        reason: String,
        afterUserDrag: Bool = false,
        keepingAuthored: Bool = false,
        alwaysHiddenShownAtDrop: Bool? = nil
    ) {
        guard arrangementIsManual || afterUserDrag, let appState, let observed = currentObservedMembership() else { return }
        switch observed.reading {
        case .ordered:
            break
        case .unavailable:
            MenuBarItemManager.diagLog.debug("observed membership (\(reason)): divider weights unavailable; skipping")
        case .outOfOrder:
            MenuBarItemManager.diagLog.warning(
                "observed membership (\(reason)): dividers out of order (\(observed.found.logString)); skipping"
            )
        }
        let baseline = afterUserDrag ? dragMembership.baseline : nil
        if afterUserDrag, baseline == nil {
            MenuBarItemManager.diagLog.debug("observed membership (\(reason)): no reading from the drag's start; skipping")
            return
        }
        if afterUserDrag {
            let grabbed = dragMembership.pressed.map { $0.map(\.description).sorted().joined(separator: ", ") } ?? "unknown"
            MenuBarItemManager.diagLog.debug("observed membership (\(reason)): grabbed \(grabbed)")
        }
        let moves = observed.reading.moves(
            for: observed.candidates,
            keepingAuthored: keepingAuthored,
            since: baseline,
            pressed: afterUserDrag ? dragMembership.pressed : nil,
            alwaysHiddenShownAtDrop: alwaysHiddenShownAtDrop
        )
        for (section, sectionItems) in moves {
            MenuBarItemManager.diagLog.info(
                "observed membership (\(reason)): \(sectionItems.count) item(s) sit in \(section.logString) on the bar: " +
                    sectionItems.map(\.logString).joined(separator: ", ")
            )
            _ = appState.menuBarManager.setSection(section, items: sectionItems)
        }
    }

    /// The stored weights read against the dividers, with the items a reading may move. Nil when the table can't be read.
    private func currentObservedMembership() -> (
        found: ObservedMembership.DividerWeights,
        reading: ObservedMembership.DividerReading,
        candidates: [ObservedMembership.Candidate]
    )? {
        guard let controller = appState?.menuBarManager.sectionController else { return nil }
        let items = itemCache.managedItems
        let weights = StoredWeights(among: items)
        guard weights.isAvailable else { return nil }
        let weight = weights.weight(of:)
        let found = ObservedMembership.DividerWeights(among: items, dividers: cacheDividers(), weight: weight)
        let experimentalSystemItemHiding = configuration.enableExperimentalSystemItemHiding
        let candidates = ObservedMembership.candidates(
            among: items,
            weight: { weight($0).flatMap { weights.isParked($0) ? nil : $0 } },
            assignment: controller.sectionAssignment,
            isEligible: {
                !$0.isControlItem && $0.tag.canBeHidden
                    && $0.isMovable(experimentalSystemItemHiding: experimentalSystemItemHiding)
            }
        )
        return (found, found.reading(alwaysHiddenEnabled: configuration.isAlwaysHiddenSectionEnabled), candidates)
    }

    /// Nothing restores a concealed section on reveal in Manual, so an explicit Layout edit writes its weights now.
    /// A live section is left to the edit's own move, and Automatic to its reveal restore.
    func writeConcealedOrderForManualEdit(in section: MenuBarSection.Name) {
        guard arrangementIsManual, ExplicitLayoutEdit.isActive, section != .visible,
              !menuBarAgentIgnoresPreferredPositions,
              let controller = appState?.menuBarManager.sectionController
        else { return }
        let revealed = controller.revealedSection
        guard revealed != section, !(section == .hidden && revealed == .alwaysHidden),
              !refuseMenuBarMutationWhileScreenLocked("concealed order write")
        else { return }
        let cachedItems = itemCache.managedItems
        let cachedIdentifiers = Set(cachedItems.map(\.uniqueIdentifier))
        let desiredOrder = (controller.sectionItemOrder[section] ?? [])
            .filter { controller.section(for: $0) == section && cachedIdentifiers.contains($0) }
        guard desiredOrder.count > 1 else { return }
        let changed = repairs.writeNow(.manualLayoutEdit, cause: .userEdit) { permit in
            MenuBarPositionStoreProvider.forLayoutEdit.respaceOrder(
                desiredOrder: desiredOrder,
                liveItems: cachedItems,
                experimentalSystemItemHiding: configuration.enableExperimentalSystemItemHiding,
                mayRewriteAroundUnplaceableItems: true,
                permit: permit
            )
        }
        guard !changed.isEmpty else { return }
        commitPreferredPositionWrite(controller: controller)
        MenuBarItemManager.diagLog.info(
            "manual arrangement: wrote \(changed.count) concealed \(section.logString) weight(s) for a Layout edit"
        )
    }

    /// Waits for the position table to settle before adopting membership.
    func scheduleObservedMembershipAdoption(
        reason: String,
        afterUserDrag: Bool = false,
        keepingAuthored: Bool = false,
        alwaysHiddenShownAtDrop: Bool? = nil
    ) {
        guard arrangementIsManual || afterUserDrag else { return }
        manualMembershipTask?.cancel()
        if !afterUserDrag {
            dragMembership.clear()
        }
        manualMembershipTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.manualMembershipSettle)
            guard !Task.isCancelled, let self else { return }
            await cacheItemsRegardless(skipRecentMoveCheck: true, skipSavedLayoutApply: true)
            guard !Task.isCancelled else { return }
            adoptObservedMembership(
                reason: reason,
                afterUserDrag: afterUserDrag,
                keepingAuthored: keepingAuthored,
                alwaysHiddenShownAtDrop: alwaysHiddenShownAtDrop
            )
            dragMembership.clear()
            manualMembershipTask = nil
            // The structural pass held off while this read the bar, so it runs
            // now, from the sections just read.
            scheduleStructuralNormalization(cause: afterUserDrag ? .userDragEnded : .rearmed)
        }
    }
}
