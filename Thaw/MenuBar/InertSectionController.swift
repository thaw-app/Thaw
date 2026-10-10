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

    func endClockActivationBridge() {}

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

    func resetAssignment(to _: [String: MenuBarSectionName]) {}

    func applyProfileLayout(itemSectionMap _: [String: String], itemOrder _: [String: [String]]) {}

    func show(_: MenuBarSectionName, reconcileBoundary _: Bool, synchronizeOrder _: Bool) {}

    func hideRevealedSections() {}

    func revealItemTemporarily(_: String) {}

    func scheduleTemporaryItemConceal(_: String) {}

    func setSectionOrder(_: [String], for _: MenuBarSectionName) {}

    func setSectionOrder(from _: [MenuBarItem], for _: MenuBarSectionName) {}

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

    func setSection(_: MenuBarSectionName, identifier _: String) {}

    func setSection(_: MenuBarSectionName, item _: MenuBarItem) {}

    func concealTemporarilyRevealedItem(_: String) {}

    func concealItemTemporarily(_: String) {}

    func revealTransientlyConcealedItem(_: String) {}

    func regatherGroups() {}

    func pulseRestrictionAfterReflow(liveItems _: [MenuBarItem]) -> Bool {
        false
    }

    func notePreferredPositionsSelfWrite() {}

    func refreshHidingAvailability() -> Bool {
        false
    }

    func refresh(forceRestrictionPulse _: Bool, forceReapply _: Bool) {}

    func repairGroupInvariantIfNeeded() -> MenuBarItemGroupPolicy.CanonicalizationReport? {
        nil
    }
}
