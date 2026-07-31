//
//  LayoutReconcilerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Characterization tests for LayoutReconciler, the thin composition
/// layer over the LayoutSolver planners.
///
/// Pins down: unmanagedPlacementPlan honoring saved positions over
/// NewItems fallback, resolveDestination anchor lookup with fallback,
/// and boundaryDestination semantics across sections.
@Suite("Layout reconciler")
struct LayoutReconcilerTests {
    // MARK: - Helpers

    private func item(
        bundleID: String,
        title: String,
        windowID: CGWindowID
    ) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: .appItem(bundleID: bundleID, title: title),
            windowID: windowID
        )
    }

    private func placement(
        section: String = "hidden",
        anchor: String? = nil,
        relation: MenuBarItemManager.NewItemsPlacement.Relation = .sectionDefault
    ) -> MenuBarItemManager.NewItemsPlacement {
        MenuBarItemManager.NewItemsPlacement(
            sectionKey: section,
            anchorIdentifier: anchor,
            relation: relation
        )
    }

    // MARK: - unmanagedPlacementPlan

    /// An unmanaged uid with a matching saved position returns .saved.
    @Test("An unmanaged item with a saved position keeps it")
    func unmanagedPlanFavorsSavedPosition() {
        let desired = DesiredLayout.fromSavedSectionOrder(
            ["visible": ["com.known.app:Status"]],
            newItemsPlacement: placement(section: "hidden")
        )

        let result = LayoutReconciler.unmanagedPlacementPlan(
            desired: desired,
            unmanagedUIDs: ["com.known.app:Status"],
            currentUIDs: ["com.known.app:Status"]
        )

        #expect(result["com.known.app:Status"] == .saved(section: .visible, index: 0))
    }

    /// An unmanaged uid with no saved position falls back to
    /// .newItemDefault using the DesiredLayout's NewItemsPlacement.
    @Test("An unmanaged item with no saved position falls back to the new-item default")
    func unmanagedPlanFallsBackToNewItemDefault() {
        let desired = DesiredLayout.fromSavedSectionOrder(
            [:],
            newItemsPlacement: placement(section: "hidden")
        )

        let result = LayoutReconciler.unmanagedPlacementPlan(
            desired: desired,
            unmanagedUIDs: ["com.new.app:Status"],
            currentUIDs: ["com.new.app:Status"]
        )

        #expect(result["com.new.app:Status"] == .newItemDefault(section: .hidden))
    }

    // MARK: - resolveDestination

    /// .leftOfUID with an anchor present in items resolves to
    /// .leftOfItem(anchor).
    @Test("Left of a present anchor resolves to that item")
    func resolveDestinationLeftOfPresentAnchor() {
        let anchor = item(bundleID: "com.anchor.app", title: "Anchor", windowID: 9000)
        let other = item(bundleID: "com.other.app", title: "Other", windowID: 9001)

        let result = LayoutReconciler.resolveDestination(
            .leftOfUID("com.anchor.app:Anchor"),
            items: [anchor, other],
            controlItems: MenuBarItemManager.ControlItemPair.fixture(
                hiddenAt: CGRect(x: 400, y: 0, width: 10, height: 22)
            ),
            fallbackSection: .visible
        )

        #expect(result == .leftOfItem(anchor))
    }

    /// .rightOfUID with anchor present resolves to .rightOfItem(anchor).
    @Test("Right of a present anchor resolves to that item")
    func resolveDestinationRightOfPresentAnchor() {
        let anchor = item(bundleID: "com.anchor.app", title: "Anchor", windowID: 9002)

        let result = LayoutReconciler.resolveDestination(
            .rightOfUID("com.anchor.app:Anchor"),
            items: [anchor],
            controlItems: MenuBarItemManager.ControlItemPair.fixture(
                hiddenAt: CGRect(x: 400, y: 0, width: 10, height: 22)
            ),
            fallbackSection: .visible
        )

        #expect(result == .rightOfItem(anchor))
    }

    /// When the named anchor uid has disappeared, fall back to the
    /// section boundary for the supplied fallback section.
    @Test("A missing anchor falls back to the section boundary")
    func resolveDestinationFallsBackToSectionBoundaryWhenAnchorMissing() {
        let pair = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: CGRect(x: 400, y: 0, width: 10, height: 22)
        )

        let result = LayoutReconciler.resolveDestination(
            .leftOfUID("com.absent.app:Gone"),
            items: [],
            controlItems: pair,
            fallbackSection: .hidden
        )

        // hidden boundary is .leftOfItem(hiddenControl).
        #expect(result == .leftOfItem(pair.hidden))
    }

    /// .sectionBoundary is resolved directly via boundaryDestination,
    /// independent of the fallbackSection argument.
    @Test("A section boundary uses its own section, not the fallback")
    func resolveDestinationSectionBoundaryUsesGivenSection() throws {
        let pair = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: CGRect(x: 400, y: 0, width: 10, height: 22),
            alwaysHiddenAt: CGRect(x: 200, y: 0, width: 10, height: 22)
        )

        let result = LayoutReconciler.resolveDestination(
            .sectionBoundary(.alwaysHidden),
            items: [],
            controlItems: pair,
            fallbackSection: .visible // intentionally wrong; should be ignored
        )

        let alwaysHidden = try #require(pair.alwaysHidden)
        #expect(result == .leftOfItem(alwaysHidden))
    }

    // MARK: - boundaryDestination

    /// .visible boundary places the item to the right of the hidden
    /// control item (which is the leftmost-visible insertion point).
    @Test("The visible boundary sits right of the hidden control item")
    func boundaryDestinationVisible() {
        let pair = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: CGRect(x: 400, y: 0, width: 10, height: 22)
        )

        let result = LayoutReconciler.boundaryDestination(
            for: .visible,
            controlItems: pair
        )

        #expect(result == .rightOfItem(pair.hidden))
    }

    /// .hidden boundary places the item to the left of the hidden
    /// control item.
    @Test("The hidden boundary sits left of the hidden control item")
    func boundaryDestinationHidden() {
        let pair = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: CGRect(x: 400, y: 0, width: 10, height: 22)
        )

        let result = LayoutReconciler.boundaryDestination(
            for: .hidden,
            controlItems: pair
        )

        #expect(result == .leftOfItem(pair.hidden))
    }

    /// .alwaysHidden boundary places the item to the left of the
    /// always-hidden control item when present.
    @Test("The always-hidden boundary sits left of the always-hidden control item")
    func boundaryDestinationAlwaysHiddenWithControl() throws {
        let pair = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: CGRect(x: 400, y: 0, width: 10, height: 22),
            alwaysHiddenAt: CGRect(x: 200, y: 0, width: 10, height: 22)
        )

        let result = LayoutReconciler.boundaryDestination(
            for: .alwaysHidden,
            controlItems: pair
        )

        let alwaysHidden = try #require(pair.alwaysHidden)
        #expect(result == .leftOfItem(alwaysHidden))
    }

    /// .alwaysHidden boundary falls back to the hidden control item
    /// when the always-hidden control is absent (section disabled).
    @Test("The always-hidden boundary falls back to the hidden control item when absent")
    func boundaryDestinationAlwaysHiddenWithoutControl() {
        let pair = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: CGRect(x: 400, y: 0, width: 10, height: 22)
        )

        let result = LayoutReconciler.boundaryDestination(
            for: .alwaysHidden,
            controlItems: pair
        )

        #expect(result == .leftOfItem(pair.hidden))
    }

    /// NewItemsPlacement with an anchor present in currentUIDs yields
    /// .newItemAnchored.
    @Test("A new-items anchor present in the current layout yields an anchored placement")
    func unmanagedPlanUsesNewItemsAnchorWhenPresent() {
        let desired = DesiredLayout.fromSavedSectionOrder(
            [:],
            newItemsPlacement: placement(
                section: "visible",
                anchor: "com.spotlight.app:Anchor",
                relation: .leftOfAnchor
            )
        )

        let result = LayoutReconciler.unmanagedPlacementPlan(
            desired: desired,
            unmanagedUIDs: ["com.new.app:Status"],
            currentUIDs: ["com.new.app:Status", "com.spotlight.app:Anchor"]
        )

        #expect(
            result["com.new.app:Status"] == .newItemAnchored(
                section: .visible,
                anchorUID: "com.spotlight.app:Anchor",
                relation: .leftOfAnchor
            )
        )
    }
}
