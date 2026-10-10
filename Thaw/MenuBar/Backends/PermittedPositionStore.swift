//
//  PermittedPositionStore.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import PlatformRuntimeKit

/// The position table as the app sees it: anyone may read, a write needs a
/// ``StoreWritePermit``.
///
/// It wraps whichever store the arrangement mode selects, so Manual's refusal
/// to reorder still applies underneath. Nothing here decides whether a write
/// should happen; it only checks that the caller was let in.
@MainActor
struct PermittedPositionStore {
    private let base: any MenuBarPositionStoring

    init(wrapping base: any MenuBarPositionStoring) {
        self.base = base
    }

    /// Whether ordering writes are refused underneath, as in manual arrangement.
    var refusesOrdering: Bool {
        base is ReadOnlyPositionStore
    }

    // MARK: Reading

    func currentPositions() -> [String: Int] {
        base.currentPositions()
    }

    func readPositions() -> [String: Int] {
        base.readPositions()
    }

    func positionsDomainIsAccessible() -> Bool {
        base.positionsDomainIsAccessible()
    }

    func resolveKey(
        for item: MenuBarItem,
        existingKeys: [String],
        positions: [String: Int],
        liveItems: [MenuBarItem]
    ) -> String? {
        base.resolveKey(for: item, existingKeys: existingKeys, positions: positions, liveItems: liveItems)
    }

    func parseStatusKey(_ key: String) -> PositionStatusKey? {
        base.parseStatusKey(key)
    }

    func isParkedWeight(_ weight: Int) -> Bool {
        base.isParkedWeight(weight)
    }

    func isProvenAbsent(_ key: String) -> Bool {
        base.isProvenAbsent(key)
    }

    // MARK: Writing

    @discardableResult
    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        permit: borrowing StoreWritePermit
    ) -> Bool {
        StoreWriteAudit.note(permit, write: "move")
        return base.move(
            item: item,
            to: destination,
            liveItems: liveItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        )
    }

    @discardableResult
    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        mayRewriteAroundUnplaceableItems: Bool,
        permit: borrowing StoreWritePermit
    ) -> Bool {
        StoreWriteAudit.note(permit, write: "move")
        return base.move(
            item: item,
            to: destination,
            liveItems: liveItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding,
            mayRewriteAroundUnplaceableItems: mayRewriteAroundUnplaceableItems
        )
    }

    func applyOrder(
        desiredOrder: [String],
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        permit: borrowing StoreWritePermit
    ) -> [String] {
        StoreWriteAudit.note(permit, write: "applyOrder")
        return base.applyOrder(
            desiredOrder: desiredOrder,
            liveItems: liveItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        )
    }

    func applyOrder(
        desiredOrder: [String],
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        mayRewriteAroundUnplaceableItems: Bool,
        permit: borrowing StoreWritePermit
    ) -> [String] {
        StoreWriteAudit.note(permit, write: "applyOrder")
        return base.applyOrder(
            desiredOrder: desiredOrder,
            liveItems: liveItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding,
            mayRewriteAroundUnplaceableItems: mayRewriteAroundUnplaceableItems
        )
    }

    func respaceOrder(
        desiredOrder: [String],
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        permit: borrowing StoreWritePermit
    ) -> [String] {
        StoreWriteAudit.note(permit, write: "respaceOrder")
        return base.respaceOrder(
            desiredOrder: desiredOrder,
            liveItems: liveItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        )
    }

    func respaceOrder(
        desiredOrder: [String],
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        mayRewriteAroundUnplaceableItems: Bool,
        permit: borrowing StoreWritePermit
    ) -> [String] {
        StoreWriteAudit.note(permit, write: "respaceOrder")
        return base.respaceOrder(
            desiredOrder: desiredOrder,
            liveItems: liveItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding,
            mayRewriteAroundUnplaceableItems: mayRewriteAroundUnplaceableItems
        )
    }

    func breakTiedSiblingWeights(
        liveItems: [MenuBarItem],
        permit: borrowing StoreWritePermit
    ) -> [String] {
        StoreWriteAudit.note(permit, write: "breakTiedSiblingWeights")
        return base.breakTiedSiblingWeights(liveItems: liveItems)
    }

    func applyControlItemOrder(
        desiredOrder: [MenuBarItem],
        opaqueVisibleKeys: [String],
        liveItems: [MenuBarItem],
        permit: borrowing StoreWritePermit
    ) -> [String] {
        StoreWriteAudit.note(permit, write: "applyControlItemOrder")
        return base.applyControlItemOrder(
            desiredOrder: desiredOrder,
            opaqueVisibleKeys: opaqueVisibleKeys,
            liveItems: liveItems
        )
    }

    func writePositions(_ positions: [String: Int], permit: borrowing StoreWritePermit) {
        StoreWriteAudit.note(permit, write: "writePositions")
        base.writePositions(positions)
    }

    // MARK: Writes the kit exposes outside the store protocol

    /// Repairs the one row that puts Siri back at the trailing edge.
    static func repairTrailingSiri(
        liveItems: [MenuBarItem],
        permit: borrowing StoreWritePermit
    ) -> [String] {
        StoreWriteAudit.note(permit, write: "repairTrailingSiri")
        return RuntimePositionStore.repairTrailingSiri(liveItems: liveItems)
    }

    /// Carries a same-app cluster across a section divider in one write.
    static func writeClusterBoundaryCrossing(
        items: [MenuBarItem],
        dividerItem: MenuBarItem,
        side: RuntimePositionStore.BoundarySide,
        liveItems: [MenuBarItem],
        permit: borrowing StoreWritePermit
    ) -> Bool {
        StoreWriteAudit.note(permit, write: "writeClusterBoundaryCrossing")
        return RuntimePositionStore.writeClusterBoundaryCrossing(
            items: items,
            dividerItem: dividerItem,
            side: side,
            liveItems: liveItems
        )
    }
}
