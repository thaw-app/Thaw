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
/// Only fresh AX answers belong here, each listing all of an app's items. A cached snapshot can
/// hold several old titles of one app, so its one item looks like many and the rename goes unseen.
public struct FreshVolatileTitleLearner: Sendable {
    private struct Observation: Sendable {
        let title: String
        let slotX: CGFloat
        let sourcePID: pid_t
        let read: UInt64

        /// The observation for an item with a title and a frame on the bar, or nil.
        static func make(for item: MenuBarItem, sourcePID: pid_t, read: UInt64) -> Self? {
            guard !item.tag.title.isEmpty, item.bounds.width > 0, item.bounds.midX >= 0
            else {
                return nil
            }
            return Self(
                title: item.tag.title,
                slotX: item.bounds.midX,
                sourcePID: sourcePID,
                read: read
            )
        }
    }

    /// A kept title older than this many reads is too old to compare, since the app may have replaced its item.
    static let maxReadsBetweenTitles: UInt64 = 4

    private var lastObservationByOwner = [String: Observation]()
    /// Bundles seen from two live processes, with those processes. A read can skip one of them, so they
    /// are not learned while both run. A relaunch overlaps its old process for a moment and looks the same.
    private var sharedBundles = [String: Set<pid_t>]()
    private var reads: UInt64 = 0

    /// A learner that has seen no inventory yet.
    public init() {}

    /// Returns owners whose title changed while their single menu bar slot stayed in place and the
    /// same process kept publishing it. An app a read skipped keeps its last title for a few reads.
    /// - Parameter isAlive: Whether a process still runs, to tell a relaunch from a second process.
    public mutating func observe(
        _ freshItems: [MenuBarItem],
        isAlive: (pid_t) -> Bool = { kill($0, 0) == 0 || errno == EPERM }
    ) -> Set<String> {
        reads &+= 1
        var itemsByOwner = [String: [MenuBarItem]]()
        for item in freshItems {
            guard !item.isControlItem, !item.isSystemClone, item.sourcePID != nil, let bundleID = item.tag.namespace.bundleIdentifier, !MenuBarItemTag.hasCanonicalizableTitles(bundleID)
            else {
                continue
            }
            itemsByOwner[bundleID, default: []].append(item)
        }

        var learned = Set<String>()
        for (bundleID, items) in itemsByOwner {
            if let processes = sharedBundles[bundleID] {
                guard processes.count(where: isAlive) < 2 else { continue }
                sharedBundles[bundleID] = nil
            }
            let previous = lastObservationByOwner.removeValue(forKey: bundleID)
            let sourcePIDs = Set(items.compactMap(\.sourcePID))
            if sourcePIDs.count > 1 {
                sharedBundles[bundleID] = sourcePIDs
                continue
            }
            guard items.count == 1, let item = items.first, let sourcePID = item.sourcePID, let observation = Observation.make(for: item, sourcePID: sourcePID, read: reads)
            else {
                continue
            }
            if let previous, previous.sourcePID != sourcePID, isAlive(previous.sourcePID) {
                sharedBundles[bundleID] = [previous.sourcePID, sourcePID]
                continue
            }
            if let previous, reads - previous.read <= Self.maxReadsBetweenTitles, Self.isRename(from: previous, to: observation) {
                learned.insert(bundleID)
            }
            lastObservationByOwner[bundleID] = observation
        }
        return learned
    }

    /// Whether the same process renamed its item in place. A change to or from a placeholder
    /// such as Item-0 is the app finishing its launch, so it doesn't count.
    private static func isRename(from old: Observation, to new: Observation) -> Bool {
        old.sourcePID == new.sourcePID && old.title != new.title && abs(old.slotX - new.slotX) <= 4
            && !MenuBarItemTag.isGenericItemTitle(old.title) && !MenuBarItemTag.isGenericItemTitle(new.title)
    }
}
