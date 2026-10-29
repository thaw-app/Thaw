//
//  InertSectionController.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

/// A no-op section controller used until performSetup(with:) supplies the
/// real one, so callers never need to check whether a controller exists.
@MainActor
final class InertSectionController: MenuBarSectionControlling {
    var sectionAssignment: [String: MenuBarSectionName] {
        [:]
    }

    var isOperational: Bool {
        false
    }

    var revealedSection: MenuBarSectionName? {
        nil
    }

    var isHidingAvailable: Bool {
        false
    }

    var isRestrictionApplied: Bool {
        false
    }

    func section(for _: MenuBarItem) -> MenuBarSectionName {
        .visible
    }

    func section(for _: String) -> MenuBarSectionName {
        .visible
    }

    /// With no engine running, nothing is on screen under our control, so a
    /// managed section reads as hidden.
    func isSectionHidden(_: MenuBarSectionName) -> Bool {
        true
    }

    func isNativeOverflowActive(on _: CGDirectDisplayID) -> Bool {
        false
    }

    func nativeOverflowControlBounds(on _: CGDirectDisplayID) -> [CGRect] {
        []
    }

    func beginClockActivationBridge(scope _: ClockActivationBridgeScope) -> Bool {
        false
    }

    func endClockActivationBridge() { /* Nothing to do until setup supplies the real controller. */ }

    func displayOrdered(_ items: [MenuBarItem], in _: MenuBarSectionName) -> [MenuBarItem] {
        items
    }

    func ordered(_ items: [MenuBarItem], in _: MenuBarSectionName) -> [MenuBarItem] {
        items
    }

    func authoredSection(for _: String) -> MenuBarSectionName {
        .visible
    }

    func snapshot(for _: String) -> MenuBarItem? {
        nil
    }

    func setOverflowHiddenIdentifiers(_: Set<String>) -> Bool {
        false
    }

    func setOverflowHiddenItems(_: [MenuBarItem]) -> Bool {
        false
    }

    var overflowHiddenIdentifiers: Set<String> {
        []
    }

    func resetAssignment(to _: [String: MenuBarSectionName]) { /* Nothing to do until setup supplies the real controller. */ }

    func applyProfileLayout(itemSectionMap _: [String: String], itemOrder _: [String: [String]]) { /* Nothing to do until setup supplies the real controller. */ }

    func show(_: MenuBarSectionName, reconcileBoundary _: Bool, synchronizeOrder _: Bool) { /* Nothing to do until setup supplies the real controller. */ }

    func hideRevealedSections() { /* Nothing to do until setup supplies the real controller. */ }

    func revealItemTemporarily(_: String) { /* Nothing to do until setup supplies the real controller. */ }

    func scheduleTemporaryItemConceal(_: String) { /* Nothing to do until setup supplies the real controller. */ }

    func setSectionOrder(_: [String], for _: MenuBarSectionName) { /* Nothing to do until setup supplies the real controller. */ }

    func setSectionOrder(from _: [MenuBarItem], for _: MenuBarSectionName) { /* Nothing to do until setup supplies the real controller. */ }

    var sectionItemOrder: [MenuBarSectionName: [String]] {
        [:]
    }

    var assignedSnapshotTags: Set<MenuBarItemTag> {
        []
    }

    var effectivelyConcealedIdentifiers: Set<String> {
        []
    }

    var shouldBridgeClockActivation: Bool {
        false
    }

    func setSection(_: MenuBarSectionName, identifier _: String) { /* Nothing to do until setup supplies the real controller. */ }

    func setSection(_: MenuBarSectionName, item _: MenuBarItem) { /* Nothing to do until setup supplies the real controller. */ }

    func concealTemporarilyRevealedItem(_: String) { /* Nothing to do until setup supplies the real controller. */ }

    func concealItemTemporarily(_: String) { /* Nothing to do until setup supplies the real controller. */ }

    func revealTransientlyConcealedItem(_: String) { /* Nothing to do until setup supplies the real controller. */ }

    func regatherGroups() { /* Nothing to do until setup supplies the real controller. */ }

    func pulseRestrictionAfterReflow(liveItems _: [MenuBarItem]) -> Bool {
        false
    }

    func notePreferredPositionsSelfWrite() { /* Nothing to do until setup supplies the real controller. */ }

    func refreshHidingAvailability() -> Bool {
        false
    }

    func refresh(forceRestrictionPulse _: Bool, forceReapply _: Bool) { /* Nothing to do until setup supplies the real controller. */ }

    func repairGroupInvariantIfNeeded() -> MenuBarItemGroupPolicy.CanonicalizationReport? {
        nil
    }
}
