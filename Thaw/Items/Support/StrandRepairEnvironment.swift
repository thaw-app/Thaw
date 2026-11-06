//
//  StrandRepairEnvironment.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// The bar, the position table and the drags the strand repair works through.
@MainActor
protocol StrandRepairEnvironment {
    var arrangementIsManual: Bool { get }
    /// Startup settling holds the bar, or the person is arranging it.
    var isBarBusy: Bool { get }
    /// Without access to the position table, MenuBarAgent never reads a write.
    var agentIgnoresPreferredPositions: Bool { get }
    var displayBounds: [CGRect] { get }

    /// The display whose application menu wraps past the notch, if any.
    func displayWhereApplicationMenuWrapsPastNotch() -> CGDirectDisplayID?
    func readBar() async -> [MenuBarItem]
    func isHiddenBySystemPreferences(_ item: MenuBarItem) -> Bool

    func moveInStore(
        _ item: MenuBarItem,
        to destination: MoveDestination,
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        permit: borrowing StoreWritePermit
    ) -> Bool
    func restoreStructuralControlOrder(controlItems: ControlItemPair, items: [MenuBarItem], permit: borrowing StoreWritePermit) -> Bool
    /// Writes a same-app cluster across the divider destination names, in one write.
    func crossClusterBoundary(
        _ cluster: [MenuBarItem],
        at destination: MoveDestination,
        liveItems: [MenuBarItem],
        permit: borrowing StoreWritePermit
    ) -> Bool
    /// Respaces the whole visible order for a strand. Returns the identifiers whose weight changed.
    func respaceVisibleLadder(
        _ order: [String],
        for strand: MenuBarItem,
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        permit: borrowing StoreWritePermit
    ) -> [String]
    func commitPreferredPositionWrite(controller: any MenuBarSectionControlling)

    func waitForUserToPauseInput(timeout: Duration) async -> Bool
    func move(item: MenuBarItem, to destination: MoveDestination, options: ItemMoveOptions) async throws -> Bool

    /// Marks an item stranded across launches.
    func recordStrand(_ item: MenuBarItem)
    func currentPositions() -> [String: Int]
}

/// The item manager's bar, store and drags, for the strand repair.
@MainActor
struct ItemManagerStrandRepairEnvironment: StrandRepairEnvironment {
    let manager: MenuBarItemManager

    var arrangementIsManual: Bool {
        manager.arrangementIsManual
    }

    var isBarBusy: Bool {
        manager.barSettling.isSettling || manager.isUserArrangingMenuBar
    }

    var agentIgnoresPreferredPositions: Bool {
        manager.menuBarAgentIgnoresPreferredPositions
    }

    var displayBounds: [CGRect] {
        BarAxis.liveDisplayBounds()
    }

    func displayWhereApplicationMenuWrapsPastNotch() -> CGDirectDisplayID? {
        guard let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main else { return nil }
        return MenuBarCapacitySnapshot.applicationMenuWrapsPastNotch(on: screen) ? screen.displayID : nil
    }

    func readBar() async -> [MenuBarItem] {
        await MenuBarItem.getMenuBarItems(option: .activeSpace)
    }

    func isHiddenBySystemPreferences(_ item: MenuBarItem) -> Bool {
        MenuBarItemManager.isHiddenBySystemPreferences(item)
    }

    func moveInStore(
        _ item: MenuBarItem,
        to destination: MoveDestination,
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        permit: borrowing StoreWritePermit
    ) -> Bool {
        MenuBarPositionStoreProvider.current.move(
            item: item,
            to: destination,
            liveItems: liveItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding,
            permit: permit
        )
    }

    func restoreStructuralControlOrder(controlItems: ControlItemPair, items: [MenuBarItem], permit: borrowing StoreWritePermit) -> Bool {
        manager.restoreStructuralControlOrder(controlItems: controlItems, items: items, permit: permit)
    }

    func crossClusterBoundary(
        _ cluster: [MenuBarItem],
        at destination: MoveDestination,
        liveItems: [MenuBarItem],
        permit: borrowing StoreWritePermit
    ) -> Bool {
        let trace = manager.tracePositionWrite(
            context: "boundary repair cluster crossing \(destination.logString)",
            items: liveItems,
            desiredOrder: cluster.map(\.uniqueIdentifier)
        )
        let crossed = PermittedPositionStore.writeClusterBoundaryCrossing(
            items: cluster,
            dividerItem: destination.targetItem,
            side: MoveTargeting.crossingSide(of: destination),
            liveItems: liveItems,
            permit: permit
        )
        trace?.finish(result: "crossed=\(crossed)")
        return crossed
    }

    func respaceVisibleLadder(
        _ order: [String],
        for strand: MenuBarItem,
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        permit: borrowing StoreWritePermit
    ) -> [String] {
        let trace = manager.tracePositionWrite(
            context: "boundary repair visible respace for \(strand.uniqueIdentifier)",
            items: liveItems,
            desiredOrder: order
        )
        let changed = MenuBarPositionStoreProvider.current.respaceOrder(
            desiredOrder: order,
            liveItems: liveItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding,
            // The boundary repair answers a reveal the user asked for; see the
            // interleaved-unplaceable note in the structural normalization.
            mayRewriteAroundUnplaceableItems: true,
            permit: permit
        )
        trace?.finish(result: String(describing: changed))
        return changed
    }

    func commitPreferredPositionWrite(controller: any MenuBarSectionControlling) {
        manager.commitPreferredPositionWrite(controller: controller)
    }

    func waitForUserToPauseInput(timeout: Duration) async -> Bool {
        await manager.waitForUserToPauseInput(timeout: timeout)
    }

    func move(item: MenuBarItem, to destination: MoveDestination, options: ItemMoveOptions) async throws -> Bool {
        try await manager.move(item: item, to: destination, options: options)
    }

    func recordStrand(_ item: MenuBarItem) {
        manager.failureLedger.recordStrand(for: item)
    }

    func currentPositions() -> [String: Int] {
        MenuBarPositionStoreProvider.current.currentPositions()
    }
}
