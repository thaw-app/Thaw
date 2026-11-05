//
//  FreshVolatileTitleLearner.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Learns which single-item apps use their whole title as a live status.
///
/// Only complete, fresh AX inventories belong here. Cached conceal snapshots
/// can contain several historical titles from one app, which is exactly the
/// condition that prevents a title-changing owner from being recognized.
public struct FreshVolatileTitleLearner: Sendable {
    private struct Observation: Sendable {
        let title: String
        let slotX: CGFloat
        let sourcePID: pid_t

        static func make(for item: MenuBarItem, sourcePID: pid_t) -> Self? {
            guard !item.tag.title.isEmpty, item.bounds.width > 0, item.bounds.midX >= 0
            else {
                return nil
            }
            return Self(
                title: item.tag.title,
                slotX: item.bounds.midX,
                sourcePID: sourcePID
            )
        }
    }

    private var lastObservationByOwner = [String: Observation]()

    public init() {}

    /// Returns owners whose title changed while their single menu bar slot
    /// stayed in place and the same process kept publishing it.
    public mutating func observe(_ freshItems: [MenuBarItem]) -> Set<String> {
        var itemsByOwner = [String: [MenuBarItem]]()
        for item in freshItems {
            guard !item.isControlItem, !item.isSystemClone, item.sourcePID != nil, case let .string(bundleID) = item.tag.namespace, !MenuBarItemTag.hasCanonicalizableTitles(bundleID)
            else {
                continue
            }
            itemsByOwner[bundleID, default: []].append(item)
        }

        var learned = Set<String>()
        var nextObservations = [String: Observation]()
        for (bundleID, items) in itemsByOwner where items.count == 1 {
            guard let item = items.first, let sourcePID = item.sourcePID, let observation = Observation.make(for: item, sourcePID: sourcePID)
            else {
                continue
            }
            if let previous = lastObservationByOwner[bundleID], previous.sourcePID == observation.sourcePID, previous.title != observation.title, abs(previous.slotX - observation.slotX) <= 4 {
                learned.insert(bundleID)
            }
            nextObservations[bundleID] = observation
        }
        lastObservationByOwner = nextObservations
        return learned
    }
}
