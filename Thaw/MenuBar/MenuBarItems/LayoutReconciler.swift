//
//  LayoutReconciler.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

// MARK: - DesiredLayout

/// A desired arrangement of menu bar items, expressed independently of
/// any specific trigger (profile apply, saved-section restore, etc.).
///
/// DesiredLayout is the unifying value type that makes profile specs
/// and savedSectionOrder structurally equivalent: both produce the same
/// shape of per-section ordered identifiers plus a NewItemsPlacement
/// fallback for items the user has never seen before. The reconciler
/// compares this against an ObservedLayout and emits the moves needed
/// to make reality match desire.
///
/// Pinned bundle IDs are only consumed by the profile-apply path; the
/// restore path leaves them empty.
struct DesiredLayout: Equatable {
    /// For each section, an ordered list of uniqueIdentifiers. Index 0
    /// is the leftmost-after-chevron position within the section.
    var sectionOrder: [MenuBarSection.Name: [String]]

    /// Pinned bundle IDs that are part of a profile spec but not yet
    /// associated with any particular section.
    var pinnedHiddenBundleIDs: Set<String>
    var pinnedAlwaysHiddenBundleIDs: Set<String>

    /// Placement preference for items not in sectionOrder.
    var newItemsPlacement: MenuBarItemManager.NewItemsPlacement

    /// Builds a DesiredLayout from a persisted savedSectionOrder
    /// dictionary (string-keyed) and a NewItemsPlacement preference.
    /// Used by the restore path where there is no profile spec, only
    /// the recorded saved layout.
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

    /// Returns the sectionOrder as the persisted string-keyed dict
    /// shape that existing LayoutSolver planners consume.
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

    /// Maps a persisted key string to its enum value.
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

/// A snapshot of the menu bar's current state, in the shape the
/// reconciler needs.
///
/// ObservedLayout packages the inputs the orchestrator already
/// computes (sometimes from Bridging / CacheContext, sometimes from
/// instance state) into a single typed value, so the reconciler entry
/// points have a clean signature.
struct ObservedLayout {
    let items: [MenuBarItem]
    let controlItems: MenuBarItemManager.ControlItemPair
    let sectionByWindowID: [CGWindowID: MenuBarSection.Name]
    let activelyShownTags: Set<String>
}

// MARK: - ControlUIDs

/// The three control item UIDs that mark section boundaries inside a
/// desired-layout sequence. Planners that insert items relative to a
/// section start, or compute per-section widths, take this as a single
/// parameter rather than three loose strings.
///
/// visible is the chevron UID and is absent when no chevron exists.
/// alwaysHidden is absent when the user has disabled the always-hidden
/// section. hidden is required because a working layout always has the
/// hidden divider.
struct ControlUIDs: Equatable {
    let visible: String?
    let hidden: String
    let alwaysHidden: String?
}

// MARK: - LayoutReconciler

/// Composes the LayoutSolver planners against a DesiredLayout /
/// ObservedLayout pair to produce reconciliation decisions.
///
/// LayoutReconciler does not own any state; it is a thin coordinator
/// over the existing pure planners. The boundary it draws is intent:
/// LayoutSolver answers "given these inputs, what is the next single
/// move?" at the algorithm level; LayoutReconciler answers "given this
/// desired layout and observed state, what is the next reconciliation
/// step?" at the trigger level.
///
/// PendingLedger remains separate because pending-relocation decisions
/// are not driven by DesiredLayout but by per-entry retry state. The
/// temporality split from the previous refactor still holds.
enum LayoutReconciler {
    /// Resolves an abstract LCSPlannedDestination against live items
    /// to produce a concrete MoveDestination.
    ///
    /// Forms the bridge between LayoutSolver's UID-anchored decisions
    /// and the move primitive's MenuBarItem-anchored inputs. The
    /// orchestrator that already holds the live items list and control
    /// item pair calls this just before invoking move(item:to:). If the
    /// anchor uid named by the planner has disappeared mid-cycle (the
    /// item quit, the cache reshuffled), falls back to the section
    /// boundary.
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
    /// Always targets the section's own control item: items in each
    /// section live to one side of that section's control item, so the
    /// control item is the natural insertion point. Control items have
    /// a permanent visible width when the divider style is .noDivider,
    /// ensuring there is always a physical gap between adjacent
    /// control items.
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

    /// Decides where each unmanaged item should land during a profile
    /// apply, consulting the desired layout's sectionOrder for saved
    /// positions and falling back to the NewItemsPlacement preference.
    ///
    /// Thin wrapper around LayoutSolver.planUnmanagedPlacement that
    /// accepts a DesiredLayout instead of raw savedSectionOrder +
    /// newItemsPlacement parameters. The result map is keyed by
    /// uniqueIdentifier and consumed by the profile orchestrator to
    /// position items in desiredFiltered.
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
    /// Three-pass insertion: saved placements first (sorted by section
    /// then savedIndex so left-to-right inserts land in the right
    /// relative order), then anchored placements (positioned relative
    /// to an existing UID), then default placements (appended at the
    /// section end). The function is pure: it does not consult live
    /// item state, only the abstract sequence the orchestrator has
    /// already built.
    ///
    /// The controlUIDs.visible field is the chevron UID, which marks
    /// the start of the .visible section so unmanaged items never land
    /// left of it.
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
                if let visibleCtrlUID = controlUIDs.visible,
                   let chevronIdx = desiredFiltered.firstIndex(of: visibleCtrlUID)
                {
                    return chevronIdx + 1
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

        // Pass 1: .saved placements, sorted by (section, savedIndex)
        // so left-to-right insertions land in the right relative
        // order. For each, find a predecessor in saved order that's
        // already in desiredFiltered and insert after it; else
        // insert at the section start.
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

        // Pass 2: .newItemAnchored placements. Insert relative to
        // the anchor in desiredFiltered (left or right per relation).
        for uid in unmanagedUIDs {
            if case let .newItemAnchored(section, anchorUID, relation) = placements[uid] {
                if let anchorIdx = desiredFiltered.firstIndex(of: anchorUID) {
                    let insertIdx = relation == .leftOfAnchor ? anchorIdx : anchorIdx + 1
                    desiredFiltered.insert(uid, at: insertIdx)
                } else {
                    desiredFiltered.insert(uid, at: sectionEndIndex(for: section))
                }
                sectionMap[uid] = sectionKeyString(for: section)
            }
        }

        // Pass 3: .newItemDefault placements. Insert at the section
        // end in unmanagedUIDs order so their relative ordering
        // matches the current menu bar.
        for uid in unmanagedUIDs {
            if case let .newItemDefault(section) = placements[uid] {
                desiredFiltered.insert(uid, at: sectionEndIndex(for: section))
                sectionMap[uid] = sectionKeyString(for: section)
            }
        }

        return (desiredFiltered, sectionMap)
    }
}
