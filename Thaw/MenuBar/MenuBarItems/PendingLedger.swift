//
//  PendingLedger.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

// MARK: - PendingLedger

/// History-dependent planner and data shapes for the pending-relocation
/// flow.
///
/// PendingLedger owns the per-entry retry state of temporarilyShow
/// rehides whose app quit before the rehide could fire: pending
/// relocations keyed by tag identifier, stored neighbor anchors for
/// position preservation across cycles, and the waitForRelaunch sentinel
/// that suppresses moves until the relaunch clock observes a new
/// windowID.
///
/// Paired with LayoutSolver, which owns the snapshot-pure planners.
/// The boundary follows the council's temporality split: LayoutSolver
/// decides over the current snapshot; PendingLedger decides over the
/// per-entry retry state. Cooldown semantics, return-destination
/// preservation, and sentinel parsing all live here.
enum PendingLedger {
    // MARK: - Result types

    /// A pending-relocation entry, parsed into a typed shape so the
    /// planner does not have to handle raw string sentinel formats.
    struct PendingEntry: Equatable {
        let tagIdentifier: String
        let kind: Kind

        enum Kind: Equatable {
            /// A normal pending relocation targeting a specific section.
            case section(MenuBarSection.Name)
            /// A wait-for-relaunch sentinel: the rehide hit its retry cap
            /// in this session; suppress moves until the windowID changes
            /// (app relaunch).
            case waitForRelaunch(windowID: CGWindowID, section: MenuBarSection.Name)
        }
    }

    /// A decision emitted by the pending-relocation planner.
    enum PendingMove: Equatable {
        /// Move the item to the destination; orchestrator clears the
        /// pending entry on success.
        case move(item: MenuBarItem, destination: MenuBarItemManager.MoveDestination)
        /// Clear the pending entry without moving (e.g. item is already
        /// in its target hidden section, or the recorded section was
        /// .visible).
        case clearEntry
        /// The wait-for-relaunch sentinel's windowID has changed (app
        /// relaunched); promote the sentinel to a regular section entry
        /// so the next planner call computes a normal move.
        case promoteWaitForRelaunch(section: MenuBarSection.Name)
        /// Skip this entry on this pass without state changes.
        case skip(reason: SkipReason)

        enum SkipReason: Equatable {
            /// Currently temporarily-shown; the rehide flow owns this item.
            case activelyShown
            /// The item is not present in the live menu bar (app not yet
            /// relaunched).
            case itemNotPresent
            /// Sentinel is active and the windowID hasn't changed; skip
            /// to avoid re-saturating the event semaphore.
            case waitForRelaunchActive
        }
    }

    /// Per-tag-identifier lookups planPendingMove consults to resolve
    /// a pending entry's destination. destinations is the dictionary
    /// persisted by temporarilyShow at the moment of the move; each
    /// inner entry records a neighbor's tag identifier and whether the
    /// item sat to the left or right of that neighbor. fallbackNeighbors
    /// is the live cache of nearest-neighbor tags rebuilt each cycle
    /// and is used when a stored destination's neighbor is no longer
    /// present.
    struct PendingReturnInfo: Equatable {
        let destinations: [String: [String: String]]
        let fallbackNeighbors: [String: MenuBarItemTag]
    }

    // MARK: - Planner

    /// Computes the next pending-relocation decision for a single entry.
    ///
    /// Walks the per-entry logic of relocatePendingItems: actively-shown
    /// short-circuit, waitForRelaunch sentinel handling, target-section
    /// validation, item-presence and item-already-hidden checks, then
    /// destination resolution (stored neighbor → fallback neighbor →
    /// section boundary).
    ///
    /// Pure over its inputs. The orchestrator parses the raw string
    /// sentinel format into PendingEntry and supplies live bounds via
    /// hiddenBounds and per-item bounds via boundsForWindowID. State
    /// mutation (pendingRelocations, pendingReturnDestinations) and
    /// execution (move()) stay with the orchestrator.
    nonisolated static func planPendingMove(
        entry: PendingEntry,
        items: [MenuBarItem],
        controlItems: MenuBarItemManager.ControlItemPair,
        hiddenBounds: CGRect,
        boundsForWindowID: [CGWindowID: CGRect],
        activelyShownTags: Set<String>,
        returnInfo: PendingReturnInfo
    ) -> PendingMove {
        if activelyShownTags.contains(entry.tagIdentifier) {
            return .skip(reason: .activelyShown)
        }

        let item = items.first { entry.tagIdentifier == $0.tag.tagIdentifier }

        // waitForRelaunch sentinel handling. If the windowID has changed
        // (app relaunched), we promote and let the orchestrator re-run.
        // If unchanged, skip. If item is not present at all, skip and
        // keep the entry for next launch.
        if case let .waitForRelaunch(sentinelWindowID, sentinelSection) = entry.kind {
            guard let item else {
                return .skip(reason: .itemNotPresent)
            }
            if item.windowID == sentinelWindowID {
                return .skip(reason: .waitForRelaunchActive)
            }
            return .promoteWaitForRelaunch(section: sentinelSection)
        }

        // Regular section entry from here on.
        guard case let .section(targetSection) = entry.kind else {
            return .skip(reason: .itemNotPresent)
        }

        // If the recorded section was .visible there is nothing to do.
        guard targetSection != .visible else {
            return .clearEntry
        }

        // Item must be present in the live menu bar.
        guard let item else {
            return .skip(reason: .itemNotPresent)
        }

        // If the item is already in a hidden section, clean up the
        // pending entry. The original code uses bestBounds for this
        // comparison; the orchestrator provides those bounds via
        // boundsForWindowID and the planner falls back to item.bounds
        // when no live bounds were supplied.
        let itemBounds = boundsForWindowID[item.windowID] ?? item.bounds
        guard itemBounds.minX >= hiddenBounds.maxX else {
            return .clearEntry
        }

        // Resolve destination: stored neighbor → fallback neighbor →
        // section boundary. We use exactly the same precedence the
        // original loop used.
        if let destInfo = returnInfo.destinations[entry.tagIdentifier],
           let neighborTagString = destInfo["neighbor"],
           let neighborItem = items.first(where: { neighborTagString == $0.tag.tagIdentifier })
        {
            let destination: MenuBarItemManager.MoveDestination = destInfo["position"] == "left"
                ? .leftOfItem(neighborItem)
                : .rightOfItem(neighborItem)
            return .move(item: item, destination: destination)
        }

        if let fallbackTag = returnInfo.fallbackNeighbors[entry.tagIdentifier],
           let fallbackItem = items.first(where: { $0.tag.tagIdentifier == fallbackTag.tagIdentifier })
        {
            return .move(item: item, destination: .rightOfItem(fallbackItem))
        }

        // Section-boundary fallback.
        switch targetSection {
        case .hidden:
            return .move(item: item, destination: .leftOfItem(controlItems.hidden))
        case .alwaysHidden:
            if let alwaysHidden = controlItems.alwaysHidden {
                return .move(item: item, destination: .leftOfItem(alwaysHidden))
            } else {
                return .move(item: item, destination: .leftOfItem(controlItems.hidden))
            }
        case .visible:
            return .clearEntry
        }
    }
}
