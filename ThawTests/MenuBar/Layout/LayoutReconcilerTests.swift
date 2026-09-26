//
//  LayoutReconcilerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// LayoutReconciler, the thin layer over the LayoutSolver planners.
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

        #expect(result == .leftOfItem(pair.hidden))
    }

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

    /// The hidden control item is the leftmost-visible insertion point.
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
