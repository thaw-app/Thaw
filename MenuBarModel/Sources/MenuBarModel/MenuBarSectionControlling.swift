//
//  MenuBarSectionControlling.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// On macOS 27, a held assertion suppresses Notification Center activation until concealment is lifted.
/// The bridge can lift concealment for the Clock alone or reveal the whole bar.
public enum ClockActivationBridgeScope: Sendable {
    /// Lift only the Clock's concealment, leaving other items parked.
    /// An already-visible Clock reports no change; callers should retry with global.
    case clockOnly

    /// Reveal all concealed items during the bridge.
    /// Some assertion states suppress even a visible Clock, requiring this fallback.
    case global
}

/// Shared interface for platform section controllers, keeping the app independent of concrete implementations.
/// Only the owning managers hold controllers directly.
@MainActor
public protocol MenuBarSectionControlling: HidingStateProviding {
    /// Stand-ins return false when this OS has no section engine.
    var isOperational: Bool { get }

    /// The section currently revealed, or nil when everything managed is
    /// concealed.
    var revealedSection: MenuBarSectionName? { get }

    /// Whether the platform can actually conceal items right now.
    var isHidingAvailable: Bool { get }

    /// Whether the platform's concealment restriction is currently in force.
    var isRestrictionApplied: Bool { get }

    /// The section item belongs to.
    func section(for item: MenuBarItem) -> MenuBarSectionName

    /// The section the item with identifier belongs to.
    func section(for identifier: String) -> MenuBarSectionName

    /// Whether section is currently concealed.
    func isSectionHidden(_ section: MenuBarSectionName) -> Bool

    /// Whether the system's own overflow is active on displayID, which
    /// changes what a capture of that display actually contains.
    func isNativeOverflowActive(on displayID: CGDirectDisplayID) -> Bool

    /// The screen rects of the system's own overflow control on displayID.
    func nativeOverflowControlBounds(on displayID: CGDirectDisplayID) -> [CGRect]

    /// Claims the next visible Clock click for a section reveal; returns false if unavailable.
    /// - Parameter scope: Try clockOnly to leave other items parked, then global if the scoped reveal changed nothing.
    func beginClockActivationBridge(scope: ClockActivationBridgeScope) -> Bool

    /// Releases a claim taken by beginClockActivationBridge(scope:).
    func endClockActivationBridge()

    /// The section identifier is authored into, independent of any temporary
    /// reveal currently in effect.
    func authoredSection(for identifier: String) -> MenuBarSectionName

    /// Records the identifiers parked in the system's own overflow, reporting
    /// whether the set changed.
    @discardableResult
    func setOverflowHiddenIdentifiers(_ identifiers: Set<String>) -> Bool

    /// Records the items parked in the system's own overflow, reporting
    /// whether the set changed.
    @discardableResult
    func setOverflowHiddenItems(_ items: [MenuBarItem]) -> Bool

    /// Authored-visible items parked in native overflow, as last recorded by the overflow setters and pruned by reassignment.
    /// Empty when nothing is ejected; presentation state, never persisted as a layout edit.
    var overflowHiddenIdentifiers: Set<String> { get }

    /// Replaces the whole assignment map.
    func resetAssignment(to assignment: [String: MenuBarSectionName])

    /// Applies a profile's section membership and per-section order.
    func applyProfileLayout(itemSectionMap: [String: String], itemOrder: [String: [String]])

    /// Reveals section.
    func show(
        _ section: MenuBarSectionName,
        reconcileBoundary: Bool,
        synchronizeOrder: Bool
    )

    /// Conceals whatever is revealed.
    func hideRevealedSections()

    /// Reveals a single concealed item until it is concealed again.
    func revealItemTemporarily(_ identifier: String)

    /// Schedules the re-concealment of a temporarily revealed item.
    func scheduleTemporaryItemConceal(_ identifier: String)

    /// Sets the order of section from item identifiers.
    func setSectionOrder(_ identifiers: [String], for section: MenuBarSectionName)

    /// Commits a rendered lane's order, retaining assigned Hidden/Always Hidden
    /// members omitted from the lane. Membership changes use setSection.
    func setSectionOrder(from items: [MenuBarItem], for section: MenuBarSectionName)

    /// The per-section item order, keyed by section.
    var sectionItemOrder: [MenuBarSectionName: [String]] { get }

    /// Tags of the items the current assignment covers.
    var assignedSnapshotTags: Set<MenuBarItemTag> { get }

    /// Identifiers of items concealed right now, whatever concealed them.
    var effectivelyConcealedIdentifiers: Set<String> { get }

    /// Whether a click on the clock should be bridged rather than delivered
    /// directly.
    var shouldBridgeClockActivation: Bool { get }

    /// Assigns a single item to section.
    func setSection(_ section: MenuBarSectionName, identifier: String)

    /// Assigns item to section.
    func setSection(_ section: MenuBarSectionName, item: MenuBarItem)

    /// Conceals a temporarily revealed item now.
    func concealTemporarilyRevealedItem(_ identifier: String)

    /// Transiently conceals a single currently-visible item until it is
    /// released, the mirror of revealItemTemporarily(_:).
    func concealItemTemporarily(_ identifier: String)

    /// Releases a transient conceal taken by concealItemTemporarily(_:).
    func revealTransientlyConcealedItem(_ identifier: String)

    /// Re-gathers grouped items that drifted apart.
    func regatherGroups()

    /// Re-applies the restriction after a reflow, reporting whether it acted.
    @discardableResult
    func pulseRestrictionAfterReflow(liveItems: [MenuBarItem]) -> Bool

    /// Marks Thaw's preferred-position writes so the next observation is not treated as a user reorder.
    func notePreferredPositionsSelfWrite()

    /// Re-checks whether hiding is available, returning whether it changed.
    @discardableResult
    func refreshHidingAvailability() -> Bool

    /// Re-applies assignments; forceReapply marks a user show/hide transition.
    /// User toggles must bypass anti-flap suppression to restore the just-superseded configuration.
    func refresh(forceRestrictionPulse: Bool, forceReapply: Bool)

    /// Repairs group invariants, reporting what it had to change.
    @discardableResult
    func repairGroupInvariantIfNeeded() -> MenuBarItemGroupPolicy.CanonicalizationReport?
}

public extension MenuBarSectionControlling {
    /// Reveals section with the ordinary boundary and ordering behaviour.
    func show(_ section: MenuBarSectionName) {
        show(section, reconcileBoundary: false, synchronizeOrder: true)
    }

    /// Re-applies the current assignment without forcing a restriction pulse.
    func refresh() {
        refresh(forceRestrictionPulse: false, forceReapply: false)
    }

    /// Compatibility forwarding for callers that only name the pulse flag.
    func refresh(forceRestrictionPulse: Bool) {
        refresh(forceRestrictionPulse: forceRestrictionPulse, forceReapply: false)
    }
}
