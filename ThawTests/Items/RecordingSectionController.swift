//
//  RecordingSectionController.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import PlatformRuntimeKit
@testable import Thaw

/// A section controller that keeps its own saved order, so a test can tell what Thaw handed the
/// controller and what Thaw read back from it. It takes an observed order through the kit's
/// ObservedOrderRecording, as the real controller does, and commits the way the kit does in the
/// places the order tests care about: an observed order reorders within the recorded sections, a
/// profile apply drops a cross-section duplicate, and a reset keeps Visible and empties the rest.
@MainActor
final class RecordingSectionController: MenuBarSectionControlling, ObservedOrderRecording {
    var sectionItemOrder: [MenuBarSectionName: [String]]
    private(set) var observedOrders = [[MenuBarSectionName: [String]]]()
    private(set) var observedCommits = 0

    init(order: [MenuBarSectionName: [String]] = [:]) {
        sectionItemOrder = order
    }

    @discardableResult
    func recordObservedOrder(_ observed: [MenuBarSectionName: [String]]) -> Bool {
        observedOrders.append(observed)
        var next = sectionItemOrder
        for (section, identifiers) in observed {
            guard let recorded = next[section] else { continue }
            let observedMembers = identifiers.filter(Set(recorded).contains)
            let observedSet = Set(observedMembers)
            var remaining = observedMembers.makeIterator()
            next[section] = recorded.map { observedSet.contains($0) ? (remaining.next() ?? $0) : $0 }
        }
        guard next != sectionItemOrder else { return false }
        sectionItemOrder = next
        observedCommits += 1
        return true
    }

    func applyProfileLayout(itemSectionMap _: [String: String], itemOrder: [String: [String]]) {
        var seen = Set<String>()
        var next = [MenuBarSectionName: [String]]()
        for section in MenuBarSectionName.allCases {
            guard let identifiers = itemOrder[section.rawValue] else { continue }
            next[section] = identifiers.filter {
                keepsInProfile($0, in: section) && seen.insert($0).inserted
            }
        }
        sectionItemOrder = next
    }

    /// Thaw's own control items stay out of a profile's order, except the Visible control in Visible.
    private func keepsInProfile(_ identifier: String, in section: MenuBarSectionName) -> Bool {
        guard identifier.contains(ControlItemIdentifier.autosavePrefix) else { return true }
        return section == .visible && identifier == MenuBarItemTag.visibleControlItem.tagIdentifier
    }

    func resetAssignment(to _: [String: MenuBarSectionName]) {
        sectionItemOrder = sectionItemOrder.filter { $0.key == .visible }
    }

    var sectionAssignment: [String: MenuBarSectionName] {
        [:]
    }

    var isOperational: Bool {
        true
    }

    var revealedSection: MenuBarSectionName? {
        nil
    }

    var isHidingAvailable: Bool {
        true
    }

    var isRestrictionApplied: Bool {
        true
    }

    var overflowHiddenIdentifiers: Set<String> {
        []
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

    func section(for _: MenuBarItem) -> MenuBarSectionName {
        .hidden
    }

    func section(for _: String) -> MenuBarSectionName {
        .hidden
    }

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
        .hidden
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

    func show(_: MenuBarSectionName, reconcileBoundary _: Bool, synchronizeOrder _: Bool) {}
    func hideRevealedSections() {}
    func revealItemTemporarily(_: String) {}
    func scheduleTemporaryItemConceal(_: String) {}
    func setSectionOrder(_: [String], for _: MenuBarSectionName) {}
    func setSectionOrder(from _: [MenuBarItem], for _: MenuBarSectionName) {}
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
