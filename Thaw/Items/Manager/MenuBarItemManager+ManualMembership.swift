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

    /// Records the end of a ⌘-drag and reads the sections it produced.
    func noteUserMenuBarDragEnded() {
        lastUserMenuBarDragEnd = .now
        scheduleObservedMembershipAdoption(reason: "⌘-drag", afterUserDrag: true)
    }

    /// Weights sort the whole bar; Hidden is beyond its divider away from Visible, Always Hidden beyond its own divider.
    /// Everything else, including items beyond the Visible control, is Visible.
    static nonisolated func observedSection(
        weight: Int,
        hiddenDivider: Int,
        alwaysHiddenDivider: Int?,
        visibleControl: Int
    ) -> MenuBarSectionName {
        // Hidden sits on the far side of its divider from the Visible control.
        let hiddenIsHigher = hiddenDivider > visibleControl
        func isBeyond(_ divider: Int) -> Bool {
            hiddenIsHigher ? weight > divider : weight < divider
        }
        if let alwaysHiddenDivider, isBeyond(alwaysHiddenDivider) {
            return .alwaysHidden
        }
        return isBeyond(hiddenDivider) ? .hidden : .visible
    }

    /// Adopt divider-weight membership without moving items: Manual after drags, mode switches, and launch; Automatic only after user drags.
    /// Leave unweighted, unhideable, Thaw Bar Only, and divider-slot items unchanged.
    func adoptObservedMembership(reason: String, afterUserDrag: Bool = false) {
        guard arrangementIsManual || afterUserDrag, let appState else { return }
        let controller = appState.menuBarManager.sectionController
        let store = MenuBarPositionStoreProvider.current
        guard store.positionsDomainIsAccessible() else { return }
        let positions = store.currentPositions()
        let items = itemCache.managedItems
        let keys = Array(positions.keys)
        func weight(of item: MenuBarItem) -> Int? {
            store.resolveKey(for: item, existingKeys: keys, positions: positions, liveItems: items)
                .flatMap { positions[$0] }
        }
        let controls = items.filter(\.isControlItem)
        guard let visibleControl = controls.first(where: { $0.tag.matchesVisibleControlItem }).flatMap(weight),
              let hiddenDivider = controls.first(where: { $0.tag == .hiddenControlItem }).flatMap(weight),
              hiddenDivider != visibleControl
        else {
            MenuBarItemManager.diagLog.debug("observed membership (\(reason)): divider weights unavailable; skipping")
            return
        }
        let alwaysHiddenDivider = configuration.isAlwaysHiddenSectionEnabled
            ? controls.first(where: { $0.tag == .alwaysHiddenControlItem }).flatMap(weight)
            : nil
        let experimentalSystemItemHiding = configuration.enableExperimentalSystemItemHiding

        var moves = [MenuBarSectionName: [MenuBarItem]]()
        for item in items where !item.isControlItem {
            guard item.tag.canBeHidden,
                  item.isMovable(experimentalSystemItemHiding: experimentalSystemItemHiding),
                  !isThawBarOnly(item),
                  let itemWeight = weight(of: item),
                  !store.isParkedWeight(itemWeight)
            else {
                continue
            }
            let observed = Self.observedSection(
                weight: itemWeight,
                hiddenDivider: hiddenDivider,
                alwaysHiddenDivider: alwaysHiddenDivider,
                visibleControl: visibleControl
            )
            guard controller.authoredSection(for: item.uniqueIdentifier) != observed else { continue }
            moves[observed, default: []].append(item)
        }
        guard !moves.isEmpty else { return }
        for (section, sectionItems) in moves.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            MenuBarItemManager.diagLog.info(
                "observed membership (\(reason)): \(sectionItems.count) item(s) sit in \(section.logString) on the bar: " +
                    sectionItems.map(\.logString).joined(separator: ", ")
            )
            _ = appState.menuBarManager.setSection(section, items: sectionItems)
        }
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
        let changed = MenuBarPositionStoreProvider.forLayoutEdit.respaceOrder(
            desiredOrder: desiredOrder,
            liveItems: cachedItems,
            experimentalSystemItemHiding: configuration.enableExperimentalSystemItemHiding,
            mayRewriteAroundUnplaceableItems: true
        )
        guard !changed.isEmpty else { return }
        commitPreferredPositionWrite(controller: controller)
        MenuBarItemManager.diagLog.info(
            "manual arrangement: wrote \(changed.count) concealed \(section.logString) weight(s) for a Layout edit"
        )
    }

    /// Waits for the position table to settle before adopting membership.
    func scheduleObservedMembershipAdoption(reason: String, afterUserDrag: Bool = false) {
        guard arrangementIsManual || afterUserDrag else { return }
        manualMembershipTask?.cancel()
        manualMembershipTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.manualMembershipSettle)
            guard !Task.isCancelled, let self else { return }
            await cacheItemsRegardless(skipRecentMoveCheck: true, skipSavedLayoutApply: true)
            guard !Task.isCancelled else { return }
            adoptObservedMembership(reason: reason, afterUserDrag: afterUserDrag)
        }
    }
}
