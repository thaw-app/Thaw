//
//  MenuBarItemManager+LayoutMoveSequence.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import PlatformRuntimeKit

/// Plans the drags of one macOS 27 section-order pass and resolves them one
/// at a time against fresh geometry.
///
/// Moves are diffed rather than replayed: a longest common subsequence
/// against the desired order drags only the items that are out of place,
/// anchored on the items that stay put. The pairwise walk in the runtime
/// coordinator is a bubble pass by comparison: for [a, x, b, c, d] wanting
/// [a, b, c, d, x] it drags b, c and d, which were already in order, and
/// never x. The plan here is exactly one move, x to the right of d.
///
/// Planning happens once per pass from the post-write snapshot; each move is
/// re-resolved against the live bar right before it is dragged, and a move
/// whose item or anchor is gone is skipped along with any moves depending on
/// it. Independent moves can finish before a bounded replan from fresh state.
extension MenuBarItemManager {
    typealias PlannedSectionMove = LayoutMoveSequencePlanner.LCSPlannedMove

    /// See Defaults.Key.useLCSSectionOrderPlanner.
    static var usesLCSSectionOrderPlanner: Bool {
        Defaults.bool(forKey: .useLCSSectionOrderPlanner)
    }

    /// Plans a section restore from the live snapshot, including the runtime's
    /// fixed-anchor segmentation. Keep this composition shared by production
    /// and tests: a correct LCS cannot detect drift if fed desired geometry.
    static func planSectionMoves(
        items: [MenuBarItem],
        desiredOrder: [String],
        section: MenuBarSection.Name,
        experimentalSystemItemHiding: Bool,
        preferredMoveUIDs: Set<String> = []
    ) -> [PlannedSectionMove] {
        // Unnamed MenuBarAgent extras are transition noise, not members: the
        // reconciler renames them when a previous walk can, and they are
        // never planned as movers when it cannot.
        let orderable = items.filter { !$0.tag.isUnnamedMenuBarAgentExtra }
        // An empty desired order asks the runtime for physical segments.
        // Passing the authored order sorts each segment into that order first,
        // so LCS compares the target with itself and emits zero moves even
        // while the revealed bar disagrees with the concealed layout row.
        let segments = MenuBarLayoutPlannerProvider.current.achievableOrderSegments(
            items: orderable,
            desiredOrder: [],
            experimentalSystemItemHiding: experimentalSystemItemHiding
        )
        return planSectionMoves(
            segments: segments.map { $0.map(\.uniqueIdentifier) },
            desiredOrder: desiredOrder,
            section: section,
            preferredMoveUIDs: preferredMoveUIDs
        )
    }

    /// The moves that bring each achievable segment to desiredOrder.
    ///
    /// Segments come from the coordinator in layout order, each already
    /// sorted left to right and bounded by fixed system anchors; the planner
    /// never moves an item across one because it only ever sees one segment
    /// at a time. desiredOrder is sliced per segment so an item authored
    /// into another segment is not planned for at all.
    ///
    /// Pure over its inputs. preferredMoveUIDs names items to prefer as movers when two
    /// subsequences tie, so a newly arrived item is the one dragged rather
    /// than an established neighbour (the overflow rebalance passes its
    /// unmanaged items).
    static nonisolated func planSectionMoves(
        segments: [[String]],
        desiredOrder: [String],
        section: MenuBarSection.Name,
        preferredMoveUIDs: Set<String> = []
    ) -> [PlannedSectionMove] {
        segments.flatMap { current -> [PlannedSectionMove] in
            let current = current.filter { !MenuBarItemTag.isUnnamedMenuBarAgentIdentifier($0) }
            let members = Set(current)
            let desired = desiredOrder.filter { members.contains($0) }
            guard desired.count > 1 else { return [] }
            let sectionMap = Dictionary(uniqueKeysWithValues: current.map { ($0, section.rawValue) })
            return LayoutMoveSequencePlanner.planLCSMoveSequence(
                currentNoControls: current,
                desiredNoControls: desired,
                sectionMap: sectionMap,
                preferredMoveUIDs: preferredMoveUIDs
            )
        }
    }

    /// Pops planned moves until one resolves against liveItems.
    ///
    /// A move is skipped, with the reason logged, when its item or anchor is
    /// no longer on the bar, when the section's divider cannot be resolved,
    /// or when the item is a trailing member of a same-app cluster: the host
    /// drags such clusters as a unit, so a drag of the trailing member snaps
    /// back. The execution queue also discards moves depending on an
    /// unconfirmed predecessor, and requests a replan once it drains.
    /// isBoundary tells the caller the target is a divider, which the move
    /// primitive refuses without its explicit opt-in.
    static func nextResolvedPlannedMove(
        from queue: inout LayoutMoveSequenceExecution,
        in liveItems: [MenuBarItem],
        controlItems: ControlItemPair?
    ) -> (item: MenuBarItem, destination: MoveDestination, isBoundary: Bool)? {
        while let planned = queue.next() {
            guard let item = liveItems.first(where: { $0.uniqueIdentifier == planned.uid }) else {
                diagLog.debug("Planned move skipped: \(planned.uid) is no longer on the bar")
                continue
            }
            if let leader = RuntimeLayoutCoordinator.sameAppClusterLeader(of: item, in: liveItems) {
                diagLog.debug(
                    "Planned move skipped: \(item.logString) trails its same-app cluster (leader \(leader.logString))"
                )
                continue
            }
            switch planned.destination {
            case let .leftOfUID(uid):
                guard let anchor = liveItems.first(where: { $0.uniqueIdentifier == uid }) else {
                    diagLog.debug("Planned move skipped: anchor \(uid) is no longer on the bar")
                    continue
                }
                return (item, .leftOfItem(anchor), false)
            case let .rightOfUID(uid):
                guard let anchor = liveItems.first(where: { $0.uniqueIdentifier == uid }) else {
                    diagLog.debug("Planned move skipped: anchor \(uid) is no longer on the bar")
                    continue
                }
                return (item, .rightOfItem(anchor), false)
            case let .sectionBoundary(name):
                guard let controlItems,
                      let destination = MenuBarLayoutPlannerProvider.current.sectionBoundaryDestination(
                          for: name,
                          controlItems: controlItems
                      )
                else {
                    diagLog.debug(
                        "Planned move skipped: \(item.logString) targets the \(name.rawValue) boundary but its divider is not on the bar"
                    )
                    continue
                }
                return (item, destination, true)
            }
        }
        return nil
    }

    /// The hidden and always-hidden divider window IDs, read from the live
    /// control items. A zero-length divider has no window, so either is nil
    /// when its section is collapsed.
    func liveControlItemWindowIDs() -> (hidden: CGWindowID?, alwaysHidden: CGWindowID?) {
        let hidden = appState?.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let alwaysHidden = appState?.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        return (hidden, alwaysHidden)
    }

    /// The divider pair resolved from items, or nil when the hidden
    /// divider is not on the bar.
    func controlItemPair(in items: [MenuBarItem]) -> ControlItemPair? {
        let windowIDs = liveControlItemWindowIDs()
        var discovery = items
        return ControlItemPair(
            items: &discovery,
            hiddenControlItemWindowID: windowIDs.hidden,
            alwaysHiddenControlItemWindowID: windowIDs.alwaysHidden
        )
    }
}
