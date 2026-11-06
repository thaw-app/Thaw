//
//  HidingStateProviding.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// The section-hiding state needed by menu bar backend abstractions without
/// coupling the shared model to a concrete controller implementation.
@MainActor
public protocol HidingStateProviding: AnyObject {
    /// The current section assignment, keyed by item identifier.
    var sectionAssignment: [String: MenuBarSectionName] { get }

    /// The section an item is currently assigned to.
    func section(for item: MenuBarItem) -> MenuBarSectionName

    /// The last-known retained snapshot for an item identifier, if any.
    func snapshot(for identifier: String) -> MenuBarItem?

    /// Orders a list of items within the given section.
    func ordered(_ items: [MenuBarItem], in section: MenuBarSectionName) -> [MenuBarItem]

    /// Orders a list of items the way the bar is currently showing them,
    /// which is not always the way they are ordered.
    ///
    /// Use this for live observations, such as checking whether a physical
    /// move succeeded. Rebucketed caches and layout editors use ordered(_:in:)
    /// instead: Hidden/Always Hidden must retain their authored order when
    /// toggles expose temporary or parked geometry.
    func displayOrdered(_ items: [MenuBarItem], in section: MenuBarSectionName) -> [MenuBarItem]
}

public extension HidingStateProviding {
    /// Providers with no way to observe the bar answer with the recorded order,
    /// which is the best they can know.
    func displayOrdered(_ items: [MenuBarItem], in section: MenuBarSectionName) -> [MenuBarItem] {
        ordered(items, in: section)
    }
}
