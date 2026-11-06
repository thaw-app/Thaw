//
//  ReadOnlyPositionStore.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import PlatformRuntimeKit

/// A position store that reads the host's table but refuses to reorder by it,
/// used in manual arrangement mode. Wrapping the store, not gating callers,
/// means persistence, hygiene and repair paths cannot re-sort the bar.
///
/// Two writes stay open. applyControlItemOrder seats Thaw's control items,
/// which are the section boundary, so blocking it would break hiding.
/// writePositions(_:) backs row removal, stale-key pruning and the
/// parked-weight restore. Foreign-item ordering reports nothing written.
@MainActor
struct ReadOnlyPositionStore: MenuBarPositionStoring {
    private static let diagLog = DiagLog(category: "ReadOnlyPositionStore")

    /// The live store, for the reads that stay honest in either mode.
    private let base: any MenuBarPositionStoring

    init(wrapping base: any MenuBarPositionStoring) {
        self.base = base
    }

    // MARK: Reading, unchanged

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
        base.resolveKey(
            for: item,
            existingKeys: existingKeys,
            positions: positions,
            liveItems: liveItems
        )
    }

    func parseStatusKey(_ key: String) -> PositionStatusKey? {
        base.parseStatusKey(key)
    }

    func isParkedWeight(_ weight: Int) -> Bool {
        base.isParkedWeight(weight)
    }

    // MARK: Ordering, refused

    @discardableResult
    func move(
        item _: MenuBarItem,
        to _: MoveDestination,
        liveItems _: [MenuBarItem],
        experimentalSystemItemHiding _: Bool
    ) -> Bool {
        false
    }

    func applyOrder(
        desiredOrder _: [String],
        liveItems _: [MenuBarItem],
        experimentalSystemItemHiding _: Bool
    ) -> [String] {
        []
    }

    func respaceOrder(
        desiredOrder _: [String],
        liveItems _: [MenuBarItem],
        experimentalSystemItemHiding _: Bool
    ) -> [String] {
        []
    }

    /// Ordering writes are refused under manual arrangement, so a tie stays
    /// wherever the user left it.
    func breakTiedSiblingWeights(liveItems _: [MenuBarItem]) -> [String] {
        []
    }

    // MARK: Thaw's own furniture, allowed

    /// Seats Thaw's control items between their neighbours, writing no
    /// member's weight. The live store's version re-ladders every item, so it
    /// is not forwarded to.
    ///
    /// A control already between its neighbours is left alone, so a settled
    /// bar writes nothing; with no free weight between them it keeps its slot.
    /// opaqueVisibleKeys is unused because nothing is permuted.
    func applyControlItemOrder(
        desiredOrder: [MenuBarItem],
        opaqueVisibleKeys _: [String],
        liveItems: [MenuBarItem]
    ) -> [String] {
        guard desiredOrder.count > 1 else { return [] }
        let positions = base.readPositions()
        guard !positions.isEmpty else { return [] }
        let existingKeys = Array(positions.keys)

        let resolved: [(item: MenuBarItem, key: String?)] = desiredOrder.map { item in
            let key = base.resolveKey(
                for: item,
                existingKeys: existingKeys,
                positions: positions,
                liveItems: liveItems
            ) ?? (item.isControlItem ? RuntimePreferenceKeys.naiveKey(for: item) : nil)
            return (item, key)
        }
        guard resolved.contains(where: { $0.item.isControlItem && $0.key != nil }) else { return [] }

        // Infer axis direction from members only; the controls are about to move.
        let memberAnchors: [(x: CGFloat, weight: Int)] = liveItems
            .filter { !$0.isControlItem && $0.isOnScreen }
            .compactMap { item in
                guard
                    let key = base.resolveKey(
                        for: item,
                        existingKeys: existingKeys,
                        positions: positions,
                        liveItems: liveItems
                    ),
                    let weight = positions[key]
                else { return nil }
                return (item.bounds.midX, weight)
            }
        let ascending = ControlItemSeating.axisAscends(members: memberAnchors)
            ?? RuntimePreferenceKeys.storeAxisAscending(in: positions)
            ?? true

        var working = positions
        var changed = [String]()
        var changedKeys = [String]()

        for (index, entry) in resolved.enumerated() {
            guard entry.item.isControlItem, let key = entry.key else { continue }
            let before = resolved[..<index].reversed()
                .compactMap { $0.key.flatMap { working[$0] } }
                .first
            let after = resolved[(index + 1)...]
                .compactMap { $0.key.flatMap { working[$0] } }
                .first
            if ControlItemSeating.isSeated(working[key], between: before, and: after, ascending: ascending) {
                continue
            }
            let taken = Set(working.filter { $0.key != key }.values)
            guard let seat = ControlItemSeating.seat(
                between: before,
                and: after,
                ascending: ascending,
                avoiding: taken
            ) else {
                Self.diagLog.debug(
                    "manual arrangement: no free slot between \(String(describing: before)) and " +
                        "\(String(describing: after)) for \(key); left where it is"
                )
                continue
            }
            working[key] = seat
            changedKeys.append(key)
            changed.append(entry.item.uniqueIdentifier)
        }

        guard !changedKeys.isEmpty else { return [] }

        // Re-read before writing so a member weight that changed meanwhile
        // is not overwritten with a stale copy.
        var fresh = base.readPositions()
        for key in changedKeys {
            fresh[key] = working[key]
        }
        base.writePositions(fresh)
        Self.diagLog.info(
            "manual arrangement: seated \(changedKeys.count) control item(s); member weights untouched"
        )
        return changed
    }

    func writePositions(_ positions: [String: Int]) {
        base.writePositions(positions)
    }

    // MARK: Absence ledger, unchanged

    func isProvenAbsent(_ key: String) -> Bool {
        base.isProvenAbsent(key)
    }

    func recordAbsenceEvidence(seen: Set<String>, blank: Set<String>) -> Set<String> {
        base.recordAbsenceEvidence(seen: seen, blank: blank)
    }

    func resetAbsenceEvidence() {
        base.resetAbsenceEvidence()
    }
}
