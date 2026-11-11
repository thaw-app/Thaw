//
//  StrandSelection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

/// Picks the visible items the strand repair moves back across the Hidden divider, and scores the pass.
/// One value lives for one pass, so each phantom frame and stale divider is logged once per pass.
@MainActor
struct StrandSelection {
    /// A strand the repair gave up on this pass, with the passes it failed in a row.
    struct Suppression {
        let strand: MenuBarItem
        let trips: Int
    }

    private let memory: BoundaryRepairMemory
    private let experimentalSystemItemHiding: Bool
    private let authoredSection: (String) -> MenuBarSectionName
    private let readWeights: () -> StoredWeights.Table
    private let weigh: (StoredWeights.Table, [MenuBarItem]) -> (MenuBarItem) -> Int?

    /// Kept until a strand is attempted, since only an attempt writes.
    private var weightTable: StoredWeights.Table?
    private var loggedPhantomIDs = Set<String>()
    private var loggedStaleDivider = false

    /// - Parameters:
    ///   - authoredSection: The section the person put an item in, by unique identifier.
    ///   - readWeights: Reads the position table; each read forces a preferences sync.
    ///   - weigh: The weight function a table gives for a set of live items.
    init(
        memory: BoundaryRepairMemory,
        experimentalSystemItemHiding: Bool,
        authoredSection: @escaping (String) -> MenuBarSectionName,
        readWeights: @escaping () -> StoredWeights.Table = { .read() },
        weigh: @escaping (StoredWeights.Table, [MenuBarItem]) -> (MenuBarItem) -> Int? = { table, items in
            let weights = StoredWeights(among: items, table: table)
            return { weights.weight(of: $0) }
        }
    ) {
        self.memory = memory
        self.experimentalSystemItemHiding = experimentalSystemItemHiding
        self.authoredSection = authoredSection
        self.readWeights = readWeights
        self.weigh = weigh
    }

    /// The visible-assigned items that fail their boundary check, or owe a physical seat, in bar order.
    mutating func failingStrands(liveItems: [MenuBarItem], controlItems: ControlItemPair) -> [MenuBarItem] {
        let table = weightTable ?? readWeights()
        weightTable = table
        let seated = DividerSeat.settled(items: liveItems, pair: controlItems, weight: weigh(table, liveItems))
        if seated.moved, !loggedStaleDivider {
            loggedStaleDivider = true
            MenuBarItemManager.diagLog.info(
                "boundary repair: the Hidden divider reports x=\(Int(controlItems.hidden.bounds.minX)) against its weight; " +
                    "judging the boundary from x=\(Int(seated.pair.hidden.bounds.minX))"
            )
        }
        return liveItems.filter { item in
            !item.isControlItem &&
                !item.isSystemClone &&
                !item.isNativeOverflowControl &&
                !isPhantomStrand(item, among: liveItems) &&
                !memory.breaker.isSuppressed(PostRestrictionRepairItemID(item)) &&
                item.isPhysicallyOrderable(experimentalSystemItemHiding: experimentalSystemItemHiding) &&
                authoredSection(item.uniqueIdentifier) == .visible &&
                (
                    // A pane transition always owes a drag: with the section collapsed, the check
                    // can't see the concealed neighbours the item stands among.
                    memory.pendingPhysicalSeatIDs.contains(item.uniqueIdentifier) ||
                        !satisfiesVisibleBoundary(items: seated.items, item: item, controlItems: seated.pair)
                )
        }
    }

    /// Drops the table read, so the next pick sees what an attempt wrote.
    mutating func forgetWeights() {
        weightTable = nil
    }

    /// Clears a repaired item's history and counts a failure for each one still stranded, once per item.
    /// - Returns: The strands that reached the trip limit this pass, now seeded so later re-arms hold.
    func scoreOutcomes(attempted: [MenuBarItem], liveItems: [MenuBarItem], controlItems: ControlItemPair) -> [Suppression] {
        var scored = Set<PostRestrictionRepairItemID>()
        var suppressed: [Suppression] = []
        for strand in attempted {
            let id = PostRestrictionRepairItemID(strand)
            guard scored.insert(id).inserted else { continue }
            if satisfiesVisibleBoundary(items: liveItems, item: strand, controlItems: controlItems) {
                memory.record(repaired: true, for: id)
                continue
            }
            let outcome = memory.record(repaired: false, for: id)
            guard outcome.suppressed else { continue }
            memory.seededStrandIDs.insert(id)
            suppressed.append(Suppression(strand: strand, trips: outcome.trips))
        }
        return suppressed
    }

    /// A phantom frame is a seat something else already occupies; dragging from it grabs that other item.
    private mutating func isPhantomStrand(_ item: MenuBarItem, among liveItems: [MenuBarItem]) -> Bool {
        guard item.hasPhantomFrame(among: liveItems) else { return false }
        if loggedPhantomIDs.insert(item.uniqueIdentifier).inserted {
            // Naming the occupant tells a second window of the same app apart from another app.
            let seatHolders = Self.seatHolders(of: item, among: liveItems).map(\.logString)
            MenuBarItemManager.diagLog.debug(
                "boundary repair: \(item.logString) has a phantom frame " +
                    "(x=\(Int(item.bounds.minX)) occupied by " +
                    "\(seatHolders.isEmpty ? "an overlapping neighbour" : seatHolders.joined(separator: ", "))); " +
                    "not draggable"
            )
        }
        return true
    }

    func satisfiesVisibleBoundary(items: [MenuBarItem], item: MenuBarItem, controlItems: ControlItemPair) -> Bool {
        MenuBarLayoutPlannerProvider.current.liveOrderSatisfiesSectionBoundary(
            items: items,
            item: item,
            section: .visible,
            controlItems: controlItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        )
    }

    /// The other windows whose frame starts where the item's does.
    static func seatHolders(of item: MenuBarItem, among liveItems: [MenuBarItem]) -> [MenuBarItem] {
        liveItems.filter {
            $0.windowID != item.windowID
                && abs($0.bounds.minX - item.bounds.minX) < MenuBarItemGeometry.phantomFrameXTolerance
        }
    }

    /// The dragged item as the refreshed walk reads it, when its frame stayed where the drag grabbed it.
    static func unmovedAfterDrag(_ dragItem: MenuBarItem, in liveItems: [MenuBarItem]) -> MenuBarItem? {
        let after = liveItems.first { $0.windowID == dragItem.windowID }
            ?? liveItems.first { $0.uniqueIdentifier == dragItem.uniqueIdentifier }
        guard let after, abs(after.bounds.minX - dragItem.bounds.minX) < MenuBarItemGeometry.phantomFrameXTolerance
        else {
            return nil
        }
        return after
    }

    /// The dividers a refreshed walk read, or nil when it lost the Hidden divider or misreads it.
    static func refreshedDividers(
        in liveItems: [MenuBarItem],
        hiddenControlItemWindowID: CGWindowID?,
        alwaysHiddenControlItemWindowID: CGWindowID?,
        displays: [CGRect] = BarAxis.liveDisplayBounds()
    ) -> ControlItemPair? {
        guard let refreshed = ControlOrderRules.refreshedControlItems(
            in: liveItems,
            hiddenControlItemWindowID: hiddenControlItemWindowID,
            alwaysHiddenControlItemWindowID: alwaysHiddenControlItemWindowID
        ) else {
            MenuBarItemManager.diagLog.debug("boundary repair: the refreshed walk lost the Hidden divider; stopping the pass")
            return nil
        }
        if let misplaced = ControlOrderRules.dividerMisplacement(refreshed, among: liveItems, displays: displays) {
            MenuBarItemManager.diagLog.debug("boundary repair: \(misplaced); stopping the pass")
            return nil
        }
        return refreshed
    }

    /// The detail logged once when a strand is suppressed. A visible-side weight still seated hidden
    /// points at the axis inference, not the write.
    static func strandDiagnostics(
        for strand: MenuBarItem,
        hiddenDivider: MenuBarItem,
        positions: [String: Int],
        weight: (MenuBarItem) -> Int?
    ) -> String {
        let frame = "frame=\(Int(strand.bounds.minX)),\(Int(strand.bounds.minY))" +
            " \(Int(strand.bounds.width))x\(Int(strand.bounds.height))"
        guard !positions.isEmpty else {
            return "\(frame) weights=unavailable"
        }
        let strandWeight = weight(strand).map(String.init) ?? "none"
        let dividerWeight = weight(hiddenDivider).map(String.init) ?? "none"
        return "\(frame) weight=\(strandWeight) hiddenDividerWeight=\(dividerWeight)"
    }
}
