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
    private(set) var sectionAssignments = [(MenuBarSectionName, String)]()
    /// setSection(_:identifier:) calls, in order.
    private(set) var identifierAssignments = [(MenuBarSectionName, String)]()
    /// What section(for:) answers per identifier; anything else is Hidden.
    var sectionsByIdentifier = [String: MenuBarSectionName]()
    /// What section(for:) answers for an item, by its unique identifier; anything else is Hidden.
    var itemSections = [String: MenuBarSectionName]()
    /// What authoredSection(for:) answers per identifier; anything else is Hidden.
    var authoredSections = [String: MenuBarSectionName]()
    private(set) var sectionOrderCalls = [(MenuBarSectionName, [String])]()
    private(set) var temporaryReveals = [String]()
    private(set) var scheduledConceals = [String]()
    private(set) var immediateConceals = [String]()

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

    var sectionAssignment: [String: MenuBarSectionName] = [:]

    var isOperational: Bool {
        true
    }

    var revealedSection: MenuBarSectionName?

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

    func section(for item: MenuBarItem) -> MenuBarSectionName {
        itemSections[item.uniqueIdentifier] ?? .hidden
    }

    func section(for identifier: String) -> MenuBarSectionName {
        sectionsByIdentifier[identifier] ?? .hidden
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

    func authoredSection(for identifier: String) -> MenuBarSectionName {
        authoredSections[identifier] ?? .hidden
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
    func revealItemTemporarily(_ identifier: String) {
        temporaryReveals.append(identifier)
    }

    func scheduleTemporaryItemConceal(_ identifier: String) {
        scheduledConceals.append(identifier)
    }

    func setSectionOrder(_: [String], for _: MenuBarSectionName) {}
    func setSectionOrder(from items: [MenuBarItem], for section: MenuBarSectionName) {
        sectionOrderCalls.append((section, items.map(\.uniqueIdentifier)))
    }

    func setSection(_ section: MenuBarSectionName, identifier: String) {
        identifierAssignments.append((section, identifier))
    }

    func setSection(_ section: MenuBarSectionName, item: MenuBarItem) {
        sectionAssignments.append((section, item.uniqueIdentifier))
    }

    func concealTemporarilyRevealedItem(_ identifier: String) {
        immediateConceals.append(identifier)
    }

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
