//
//  DividerSeat.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

/// Where a section divider sits when its reported frame has stopped following the bar.
///
/// A zero-width divider can keep reporting one x for a whole session while everything around it
/// moves. In one session the Hidden divider stayed at x=1437.5 for twenty minutes, ending up
/// inside Sound's frame, while its weight (276) put it between its left neighbour (279) and Home (266). Judged
/// against that frame, Home was judged stranded among the hidden items on every reveal, and each repair
/// rewrote its neighbours and failed.
///
/// Two things have to agree before the frame is set aside. The divider's weight must not fit between
/// the weights of the items beside its reported x, and must fit exactly one other slot. And that slot
/// must have more room than the reported one, because a divider widens the gap it really sits in.
/// An item the host seated on the wrong side leaves the divider's own gap wide, so it is still caught.
nonisolated enum DividerSeat {
    /// How much wider the gap holding the divider must be than the gap it reports.
    static let gapMargin: CGFloat = 4

    /// The divider's frame at the slot its weight names, or nil when the reported frame is believable.
    static func corrected(
        divider: MenuBarItem,
        among items: [MenuBarItem],
        weight: (MenuBarItem) -> Int?
    ) -> CGRect? {
        guard let dividerWeight = weight(divider) else { return nil }
        let neighbours: [(item: MenuBarItem, weight: Int)] = items
            .filter { !$0.isControlItem && $0.bounds.width > 0 && abs($0.bounds.midY - divider.bounds.midY) < 48 }
            .sorted { $0.bounds.minX < $1.bounds.minX }
            .compactMap { item in weight(item).map { (item, $0) } }
        guard neighbours.count > 1 else { return nil }

        let falling = zip(neighbours, neighbours.dropFirst()).count { $0.weight > $1.weight }
        let rising = zip(neighbours, neighbours.dropFirst()).count { $0.weight < $1.weight }
        guard falling != rising else { return nil }
        let isDescending = falling > rising
        func inOrder(_ left: Int, _ right: Int) -> Bool {
            isDescending ? left > right : left < right
        }
        func fits(_ slot: Int) -> Bool {
            let left = slot > 0 ? neighbours[slot - 1].weight : nil
            let right = slot < neighbours.count ? neighbours[slot].weight : nil
            return (left.map { inOrder($0, dividerWeight) } ?? true) && (right.map { inOrder(dividerWeight, $0) } ?? true)
        }
        /// The free room at a slot, or nil at either end of the run, where there is nothing to measure.
        func gap(_ slot: Int) -> ClosedRange<CGFloat>? {
            guard slot > 0, slot < neighbours.count else { return nil }
            let lower = neighbours[slot - 1].item.bounds.maxX
            let upper = neighbours[slot].item.bounds.minX
            return lower <= upper ? lower ... upper : nil
        }

        let reported = neighbours.count { $0.item.bounds.midX < divider.bounds.midX }
        guard !fits(reported) else { return nil }
        let candidates = (0 ... neighbours.count).filter(fits)
        guard candidates.count == 1, let implied = candidates.first, let impliedGap = gap(implied) else { return nil }

        // A frame that overlaps a neighbour reports no room at all.
        let reportedRoom: CGFloat = gap(reported).flatMap { room in
            room.contains(divider.bounds.minX) && room.contains(divider.bounds.maxX) ? room.upperBound - room.lowerBound : nil
        } ?? 0
        guard impliedGap.upperBound - impliedGap.lowerBound >= reportedRoom + gapMargin else { return nil }

        var frame = divider.bounds
        frame.origin.x = (impliedGap.lowerBound + impliedGap.upperBound - frame.width) / 2
        return frame
    }

    /// The items and dividers to judge a boundary against, with a stale Hidden divider put where its weight names.
    static func settled(
        items: [MenuBarItem],
        pair: ControlItemPair,
        weight: (MenuBarItem) -> Int?
    ) -> (items: [MenuBarItem], pair: ControlItemPair, moved: Bool) {
        guard let frame = corrected(divider: pair.hidden, among: items, weight: weight) else {
            return (items, pair, false)
        }
        func reseated(_ item: MenuBarItem) -> MenuBarItem {
            MenuBarItem(
                tag: item.tag,
                windowID: item.windowID,
                ownerPID: item.ownerPID,
                sourcePID: item.sourcePID,
                bounds: frame,
                title: item.title,
                isOnScreen: item.isOnScreen
            )
        }
        let hidden = reseated(pair.hidden)
        return (
            items.map { $0.windowID == pair.hidden.windowID && $0.isControlItem ? reseated($0) : $0 },
            ControlItemPair(hidden: hidden, alwaysHidden: pair.alwaysHidden),
            true
        )
    }
}
