//
//  LayoutReconciler.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

// MARK: - DesiredLayout

/// A desired arrangement of menu bar items, independent of what triggered
/// it. Profiles and savedSectionOrder both reduce to this shape.
///
/// Only profile apply uses the pinned bundle IDs.
nonisolated struct DesiredLayout: Equatable {
    /// Index 0 is the leftmost position after the chevron.
    var sectionOrder: [MenuBarSection.Name: [String]]

    /// Pinned bundle IDs that are part of a profile spec but not yet
    /// associated with any particular section.
    var pinnedHiddenBundleIDs: Set<String>
    var pinnedAlwaysHiddenBundleIDs: Set<String>

    /// For items not in sectionOrder.
    var newItemsPlacement: MenuBarItemManager.NewItemsPlacement

    /// For the restore path, which has no profile spec.
    static func fromSavedSectionOrder(
        _ savedSectionOrder: [String: [String]],
        newItemsPlacement: MenuBarItemManager.NewItemsPlacement,
        pinnedHiddenBundleIDs: Set<String> = [],
        pinnedAlwaysHiddenBundleIDs: Set<String> = []
    ) -> DesiredLayout {
        var typedOrder: [MenuBarSection.Name: [String]] = [:]
        for (key, ids) in savedSectionOrder {
            guard let section = sectionName(forPersistedKey: key) else { continue }
            typedOrder[section] = ids
        }
        return DesiredLayout(
            sectionOrder: typedOrder,
            pinnedHiddenBundleIDs: pinnedHiddenBundleIDs,
            pinnedAlwaysHiddenBundleIDs: pinnedAlwaysHiddenBundleIDs,
            newItemsPlacement: newItemsPlacement
        )
    }

    /// The string-keyed shape the LayoutSolver planners consume.
    var sectionOrderAsPersistedDict: [String: [String]] {
        var result: [String: [String]] = [:]
        for (section, ids) in sectionOrder {
            switch section {
            case .visible: result["visible"] = ids
            case .hidden: result["hidden"] = ids
            case .alwaysHidden: result["alwaysHidden"] = ids
            }
        }
        return result
    }

    private static func sectionName(forPersistedKey key: String) -> MenuBarSection.Name? {
        switch key {
        case "visible": .visible
        case "hidden": .hidden
        case "alwaysHidden": .alwaysHidden
        default: nil
        }
    }
}

// MARK: - ObservedLayout

// MARK: - ControlUIDs

/// The control item UIDs that mark section boundaries in a desired layout.
///
/// visible is the chevron and may be absent; alwaysHidden is absent when
/// that section is disabled. A working layout always has hidden.
nonisolated struct ControlUIDs: Equatable {
    let visible: String?
    let hidden: String
    let alwaysHidden: String?
}

// MARK: - LayoutReconciler

/// Composes the LayoutSolver planners against a DesiredLayout /
/// ObservedLayout pair to produce reconciliation decisions.
///
/// Stateless. LayoutSolver picks the next move from raw inputs; this works
/// at the level of a desired layout. PendingLedger stays separate because
/// it runs on per-entry retry state.
nonisolated enum LayoutReconciler {
    /// Resolves an abstract LCSPlannedDestination against live items
    /// to produce a concrete MoveDestination.
    ///
    /// Falls back to the section boundary if the anchor disappeared
    /// mid-cycle.
    static func resolveDestination(
        _ abstract: LayoutSolver.LCSPlannedDestination,
        items: [MenuBarItem],
        controlItems: MenuBarItemManager.ControlItemPair,
        fallbackSection: MenuBarSection.Name
    ) -> MenuBarItemManager.MoveDestination {
        switch abstract {
        case let .leftOfUID(anchorUID):
            if let anchor = items.first(where: {
                $0.uniqueIdentifier == anchorUID && $0.isMovable
            }) {
                return .leftOfItem(anchor)
            }
            return boundaryDestination(for: fallbackSection, controlItems: controlItems)
        case let .rightOfUID(anchorUID):
            if let anchor = items.first(where: {
                $0.uniqueIdentifier == anchorUID && $0.isMovable
            }) {
                return .rightOfItem(anchor)
            }
            return boundaryDestination(for: fallbackSection, controlItems: controlItems)
        case let .sectionBoundary(section):
            return boundaryDestination(for: section, controlItems: controlItems)
        }
    }

    /// Returns the move destination at the boundary of the given
    /// section.
    ///
    /// Always targets the section's control item. Even with .noDivider,
    /// control items keep a visible width, so there's always a gap.
    static func boundaryDestination(
        for section: MenuBarSection.Name,
        controlItems: MenuBarItemManager.ControlItemPair
    ) -> MenuBarItemManager.MoveDestination {
        switch section {
        case .visible:
            return .rightOfItem(controlItems.hidden)
        case .hidden:
            return .leftOfItem(controlItems.hidden)
        case .alwaysHidden:
            if let alwaysHidden = controlItems.alwaysHidden {
                return .leftOfItem(alwaysHidden)
            }
            return .leftOfItem(controlItems.hidden)
        }
    }

    /// Where each unmanaged item lands during a profile apply: its saved
    /// position, else the NewItemsPlacement preference.
    static func unmanagedPlacementPlan(
        desired: DesiredLayout,
        unmanagedUIDs: [String],
        currentUIDs: Set<String>
    ) -> [String: LayoutSolver.UnmanagedPlacement] {
        LayoutSolver.planUnmanagedPlacement(
            unmanagedUIDs: unmanagedUIDs,
            savedSectionOrder: desired.sectionOrderAsPersistedDict,
            newItemsPlacement: desired.newItemsPlacement,
            currentUIDs: currentUIDs
        )
    }

    /// Inserts unmanaged items into the desired-layout sequence at the
    /// positions chosen by unmanagedPlacementPlan, returning the updated
    /// sequence and section assignments.
    ///
    /// Inserts saved placements, then anchored, then defaults. Pure.
    ///
    /// Every uid in unmanagedUIDs must be absent from desiredFiltered. A uid
    /// already present is skipped, since a duplicate is unrecoverable.
    ///
    /// An anchored placement stays in the section it names, so position and
    /// sectionMap can't disagree.
    static func applyUnmanagedPlacementsToDesired(
        placements: [String: LayoutSolver.UnmanagedPlacement],
        unmanagedUIDs: [String],
        desiredFiltered: [String],
        sectionMap: [String: String],
        savedSectionOrder: [String: [String]],
        controlUIDs: ControlUIDs
    ) -> (desiredFiltered: [String], sectionMap: [String: String]) {
        var desiredFiltered = desiredFiltered
        var sectionMap = sectionMap

        func sectionStartIndex(for section: MenuBarSection.Name) -> Int {
            switch section {
            case .visible:
                // Visible is the first block, so its leftmost slot is 0.
                // The chevron can sit anywhere in it; skip only a leading one.
                if let chevron = controlUIDs.visible, desiredFiltered.first == chevron {
                    return 1
                }
                return 0
            case .hidden:
                if let hiddenIdx = desiredFiltered.firstIndex(of: controlUIDs.hidden) {
                    return hiddenIdx + 1
                }
                return desiredFiltered.endIndex
            case .alwaysHidden:
                if let ahUID = controlUIDs.alwaysHidden,
                   let ahIdx = desiredFiltered.firstIndex(of: ahUID)
                {
                    return ahIdx + 1
                }
                return desiredFiltered.endIndex
            }
        }
        func sectionEndIndex(for section: MenuBarSection.Name) -> Int {
            switch section {
            case .visible:
                return desiredFiltered.firstIndex(of: controlUIDs.hidden) ?? desiredFiltered.endIndex
            case .hidden:
                if let ahUID = controlUIDs.alwaysHidden,
                   let ahIdx = desiredFiltered.firstIndex(of: ahUID)
                {
                    return ahIdx
                }
                return desiredFiltered.endIndex
            case .alwaysHidden:
                return desiredFiltered.endIndex
            }
        }
        /// Mirrors `defaultNewItemsBadgeIndex` so the badge and a new item's
        /// slot can't disagree.
        func sectionDefaultIndex(for section: MenuBarSection.Name) -> Int {
            switch section {
            case .visible:
                return sectionStartIndex(for: .visible)
            case .hidden:
                return controlUIDs.alwaysHidden != nil
                    ? sectionStartIndex(for: .hidden)
                    : sectionEndIndex(for: .hidden)
            case .alwaysHidden:
                return sectionEndIndex(for: .alwaysHidden)
            }
        }
        /// Whether a section's default slot is at its start, where successive
        /// defaults need an offset to keep their order.
        func sectionDefaultIsAtStart(_ section: MenuBarSection.Name) -> Bool {
            switch section {
            case .visible:
                return true
            case .hidden:
                return controlUIDs.alwaysHidden != nil
            case .alwaysHidden:
                return false
            }
        }
        func sectionKeyString(for section: MenuBarSection.Name) -> String {
            switch section {
            case .visible: return "visible"
            case .hidden: return "hidden"
            case .alwaysHidden: return "alwaysHidden"
            }
        }
        func sectionOrderIndex(_ s: MenuBarSection.Name) -> Int {
            switch s {
            case .visible: return 0
            case .hidden: return 1
            case .alwaysHidden: return 2
            }
        }

        // Pass 1: .saved, sorted so inserts keep their relative order.
        // Insert after a saved-order predecessor, else at section start.
        var savedTuples: [(String, MenuBarSection.Name, Int)] = []
        for uid in unmanagedUIDs {
            if case let .saved(section, index) = placements[uid] {
                savedTuples.append((uid, section, index))
            }
        }
        savedTuples.sort { lhs, rhs in
            if sectionOrderIndex(lhs.1) != sectionOrderIndex(rhs.1) {
                return sectionOrderIndex(lhs.1) < sectionOrderIndex(rhs.1)
            }
            return lhs.2 < rhs.2
        }
        for (uid, section, savedIndex) in savedTuples {
            // Guards the caller invariant.
            if desiredFiltered.contains(uid) {
                continue
            }
            let savedSeq = savedSectionOrder[sectionKeyString(for: section)] ?? []
            let currentInSection: Set<String> = {
                var set = Set<String>()
                let start = sectionStartIndex(for: section)
                let end = sectionEndIndex(for: section)
                if start < end {
                    for u in desiredFiltered[start ..< end] {
                        set.insert(u)
                    }
                }
                return set
            }()
            let destination = LayoutSolver.anchorDestination(
                forSavedIndex: savedIndex,
                inSection: section,
                savedSequence: savedSeq,
                currentUIDsInSection: currentInSection
            )
            switch destination {
            case let .leftOfUID(anchorUID):
                if let anchorIdx = desiredFiltered.firstIndex(of: anchorUID) {
                    desiredFiltered.insert(uid, at: anchorIdx)
                } else {
                    desiredFiltered.insert(uid, at: sectionStartIndex(for: section))
                }
            case let .rightOfUID(anchorUID):
                if let anchorIdx = desiredFiltered.firstIndex(of: anchorUID) {
                    desiredFiltered.insert(uid, at: anchorIdx + 1)
                } else {
                    desiredFiltered.insert(uid, at: sectionStartIndex(for: section))
                }
            case .sectionBoundary:
                desiredFiltered.insert(uid, at: sectionStartIndex(for: section))
            }
            sectionMap[uid] = sectionKeyString(for: section)
        }

        // Pass 2: .newItemAnchored. leftOf keeps order because the anchor
        // shifts right; rightOf would reuse `anchorIdx + 1` and reverse.
        // Track the last placed uid per anchor, not an index: the clamp
        // can pin every slot to the section start, and indexes go stale.
        var lastRightOfAnchorUID = [String: String]()
        var rightOfAnchorInserted = [String: Int]()
        for uid in unmanagedUIDs {
            if case let .newItemAnchored(section, anchorUID, relation) = placements[uid] {
                // Guards the caller invariant: see pass 1.
                if desiredFiltered.contains(uid) {
                    continue
                }
                let sectionEnd = sectionEndIndex(for: section)
                var insertIdx: Int
                var placedRightOfAnchor = false
                switch relation {
                case .leftOfAnchor, .rightOfAnchor:
                    if let anchorIdx = desiredFiltered.firstIndex(of: anchorUID) {
                        let offset = relation == .rightOfAnchor
                            ? rightOfAnchorInserted[anchorUID, default: 0]
                            : 0
                        let anchored = relation == .leftOfAnchor
                            ? anchorIdx
                            : anchorIdx + 1 + offset
                        // The anchor may be in another section; clamp so
                        // position and sectionMap agree.
                        insertIdx = min(max(anchored, sectionStartIndex(for: section)), sectionEnd)
                        placedRightOfAnchor = (relation == .rightOfAnchor)
                    } else {
                        insertIdx = sectionEnd
                    }
                case .sectionDefault:
                    // Not a positioning request; use the section default.
                    insertIdx = sectionEnd
                }
                if placedRightOfAnchor,
                   let previousUID = lastRightOfAnchorUID[anchorUID],
                   let previousIdx = desiredFiltered.firstIndex(of: previousUID)
                {
                    insertIdx = min(max(insertIdx, previousIdx + 1), sectionEnd)
                }
                desiredFiltered.insert(uid, at: insertIdx)
                if placedRightOfAnchor {
                    rightOfAnchorInserted[anchorUID, default: 0] += 1
                    lastRightOfAnchorUID[anchorUID] = uid
                }
                sectionMap[uid] = sectionKeyString(for: section)
            }
        }

        // Pass 3: .newItemDefault, at the badge's default slot.
        var defaultInsertedCount = [MenuBarSection.Name: Int]()
        for uid in unmanagedUIDs {
            if case let .newItemDefault(section) = placements[uid] {
                // Guards the caller invariant: see pass 1.
                if desiredFiltered.contains(uid) {
                    continue
                }
                // A start slot is stable, so offset each insert; an end slot
                // advances on its own.
                let base = sectionDefaultIndex(for: section)
                let offset = sectionDefaultIsAtStart(section)
                    ? defaultInsertedCount[section, default: 0]
                    : 0
                desiredFiltered.insert(uid, at: base + offset)
                defaultInsertedCount[section, default: 0] += 1
                sectionMap[uid] = sectionKeyString(for: section)
            }
        }

        return (desiredFiltered, sectionMap)
    }
}
