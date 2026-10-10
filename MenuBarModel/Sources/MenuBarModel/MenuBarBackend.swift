//
//  MenuBarBackend.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Menu-bar section behavior, as policy the manager asks for rather than
/// branches on.
///
/// One adapter implements this today: RuntimeMenuBarBackend, which uses
/// assertion-backed visibility and assignment-based cache reconstruction. The
/// protocol stays because it keeps that policy out of the manager and isolates
/// the app from PlatformRuntimeKit's concrete type.
public protocol MenuBarBackend: Sendable {
    @MainActor
    func rebucket(
        _ cache: MenuBarItemCache,
        hider: (any HidingStateProviding)?,
        allowsAlwaysHidden: Bool
    ) -> MenuBarItemCache

    func capturableSections(
        from requested: [MenuBarSectionName],
        revealedSection: MenuBarSectionName?
    ) -> [MenuBarSectionName]

    /// Selects the bounds source used to validate an automatic relocation, or
    /// nil when the candidate has no usable bounds and the move should be
    /// skipped. Uses the item's own AX bounds, because synthetic window IDs
    /// make a WindowServer lookup invalid, and rejects the x == -1 /
    /// zero-size transient reads.
    nonisolated func relocationBounds(itemBounds: CGRect, windowServerBounds: CGRect?) -> CGRect?

    /// Whether an AX snapshot that is missing Thaw's own visible control item
    /// should be treated as a transient miss so the last-good cache is retained
    /// rather than overwritten with a bad frame.
    nonisolated func shouldRetainLastGoodCache(snapshotItems: [MenuBarItem], previousCachedItems: [MenuBarItem]) -> Bool

    /// Whether Thaw may synthesize its zero-length divider control items from
    /// the snapshot (only when the visible control item is actually present).
    nonisolated func canSynthesizeControlItems(snapshotItems: [MenuBarItem]) -> Bool

    /// Whether a windowID-set difference between two cache cycles is a genuine
    /// change that should trigger a saved-layout re-apply, or merely an artifact
    /// (synthetic-ID churn, where logical identity and assignment divergence
    /// own restore detection instead).
    nonisolated func windowIDsChanged(
        previous: Set<CGWindowID>,
        current: Set<CGWindowID>,
        previousDisplayID: CGDirectDisplayID?,
        currentDisplayID: CGDirectDisplayID?
    ) -> Bool

    /// Whether the current bar differs from the saved layout in section
    /// membership: the secondary applySavedLayout trigger for ambient drift
    /// that leaves window IDs intact. savedSectionByBaseID maps each saved
    /// item's namespace:title base identifier to its saved section.
    ///
    /// Membership is read from HidingStateProviding.section(for:) rather
    /// than classified spatially, because it is assignment-driven and AX
    /// X-coordinates still read hidden-side after an assertion reflow.
    /// Non-concealable Apple system items and items parked off the bar band are
    /// excluded, since they would otherwise never converge and would re-fire
    /// the bulk apply every cache cycle.
    @MainActor
    func layoutMembershipDiverged(
        savedSectionByBaseID: [String: MenuBarSectionName],
        items: [MenuBarItem],
        controlItems: ControlItemPair,
        hider: (any HidingStateProviding)?
    ) -> Bool

    /// Which layout-snapshot persistence to run when the shared persist gate is
    /// open (shouldPersist): mirrors the assignment-driven section order.
    nonisolated func persistLayoutSnapshot(shouldPersist: Bool) -> LayoutSnapshotAction

    /// Which section-divider enforcement model applies on this OS.
    nonisolated var controlItemEnforcementStrategy: ControlItemEnforcementStrategy { get }

    nonisolated var preferredMovePath: PreferredMovePath { get }

    nonisolated func allowsSectionBoundaryDividerTarget(allowExplicitOptIn: Bool) -> Bool

    nonisolated func resetExecution(for target: SectionResetTarget) -> LayoutResetExecution

    nonisolated func itemCacheSignature(_ items: [MenuBarItem]) -> [String]?

    nonisolated var profileLayoutStrategy: ProfileLayoutStrategy { get }

    nonisolated var savedLayoutRestoreStrategy: SavedLayoutRestoreStrategy { get }

    nonisolated var classifiesSectionByDividerGeometry: Bool { get }

    nonisolated var shouldCoalesceCacheRerun: Bool { get }

    nonisolated var usesProfileWindowIDRelaunchHeuristic: Bool { get }

    /// Whether item may be assigned to section at all.
    ///
    /// Assignment policy rather than controller state: the layout editor and
    /// the reset paths both need to ask before offering a move, and neither
    /// holds a controller.
    @MainActor
    func canAssign(
        _ item: MenuBarItem,
        to section: MenuBarSectionName,
        experimentalSystemItemHiding: Bool
    ) -> Bool

    /// Whether item is one the app must not reassign: its own control
    /// items, itself, and the anchored system items.
    @MainActor
    func isProtectedAssignmentItem(
        _ item: MenuBarItem,
        experimentalSystemItemHiding: Bool
    ) -> Bool

    /// Whether a whole group may move to section, which fails as a unit: a
    /// group is indivisible, so one blocked member blocks all of them.
    @MainActor
    func canMoveGroup(
        members: [MenuBarItem],
        expectedMemberCount: Int,
        to section: MenuBarSectionName,
        experimentalSystemItemHiding: Bool,
        isHidingAvailable: Bool
    ) -> Bool

    /// The trailing run of anchored system items, in the order the system
    /// pins them, which nothing may be placed after.
    @MainActor
    func anchoredSystemItemsTrail(in items: [MenuBarItem]) -> [MenuBarItem]

    /// items in visible-section order, honouring order where it applies
    /// and falling back to the live visual order where it does not.
    @MainActor
    func overflowOrderedVisibleItems(
        _ items: [MenuBarItem],
        using order: [String]
    ) -> [MenuBarItem]
}
