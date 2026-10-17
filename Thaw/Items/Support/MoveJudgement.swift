//
//  MoveJudgement.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// What the bar shows about a repair move: it took, it didn't, or the bar can't tell.
/// A move that can't be judged is set aside rather than scored, so it never escalates into a respace.
nonisolated enum MoveJudgement: Equatable {
    case applied
    case unapplied
    case unjudgeable(Reason)

    enum Reason: String {
        /// An item arrived or left between the before and after reads, so positions shifted for another reason.
        case itemCountChanged = "the item count changed"
        /// The app owns another icon, and the agent may sort them by rows the write didn't touch.
        case sharedOwner = "its app has another icon on the bar"
    }

    static func judge(repaired: Bool, itemCountBefore: Int, itemCountAfter: Int, ownerIconCount: Int) -> Self {
        if repaired {
            return .applied
        }
        if itemCountBefore != itemCountAfter {
            return .unjudgeable(.itemCountChanged)
        }
        return ownerIconCount > 1 ? .unjudgeable(.sharedOwner) : .unapplied
    }

    static func ownerIconCount(of item: MenuBarItem, among items: [MenuBarItem]) -> Int {
        items.count { !$0.isControlItem && $0.tag.namespace == item.tag.namespace }
    }
}

nonisolated extension BoundaryRepairBreaker {
    /// Unjudgeable sets the item aside for the cooldown without a trip.
    @discardableResult
    mutating func record(_ judgement: MoveJudgement, for id: ID, tripLimit: Int, now: Date = Date()) -> Outcome {
        guard case .unjudgeable = judgement else {
            return record(repaired: judgement == .applied, for: id, tripLimit: tripLimit, now: now)
        }
        rearm(id)
        suppress(id, at: now)
        return Outcome(suppressed: true, trips: 0)
    }
}
