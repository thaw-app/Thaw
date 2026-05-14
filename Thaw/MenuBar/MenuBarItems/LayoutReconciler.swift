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

// MARK: - RestoreMove

/// A single move emitted by the reconciler's restore path.
///
/// Composition of the two LayoutSolver planners that the restore
/// orchestrator was previously calling in sequence. The orchestrator
/// resolves the abstract destination on either case the same way.
enum RestoreMove: Equatable {
    /// A cross-section move from one section to another. The
    /// destination is position-aware within the target section.
    case crossSection(LayoutSolver.RebalanceMove)
    /// A within-section reorder. The item stays in its current
    /// section but moves to its saved position within it.
    case withinSection(LayoutSolver.WithinSectionMove)
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
    /// Returns the next single move needed to make the observed layout
    /// match the desired layout, or nil when no move is needed.
    ///
    /// Cross-section count mismatches are preferred over within-section
    /// order drift: the cross-section planner runs first and its
    /// result short-circuits the within-section check. Same one-move-
    /// per-call contract the underlying planners offer; the caller
    /// recaches and re-enters until the reconciler returns nil.
    static func nextRestoreMove(
        desired: DesiredLayout,
        observed: ObservedLayout,
        hasAlwaysHiddenSection: Bool
    ) -> RestoreMove? {
        let savedSectionOrder = desired.sectionOrderAsPersistedDict

        if let cross = LayoutSolver.planRebalanceMove(
            items: observed.items,
            sectionByWindowID: observed.sectionByWindowID,
            hasAlwaysHiddenSection: hasAlwaysHiddenSection,
            savedSectionOrder: savedSectionOrder,
            activelyShownTags: observed.activelyShownTags
        ) {
            return .crossSection(cross)
        }

        if let within = LayoutSolver.planWithinSectionReorder(
            items: observed.items,
            sectionByWindowID: observed.sectionByWindowID,
            savedSectionOrder: savedSectionOrder,
            activelyShownTags: observed.activelyShownTags,
            hasAlwaysHiddenSection: hasAlwaysHiddenSection
        ) {
            return .withinSection(within)
        }

        return nil
    }

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
}
