//
//  LayoutReconcilerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw
import XCTest

/// Characterization tests for LayoutReconciler, the thin composition
/// layer over the LayoutSolver planners.
///
/// Pins down: unmanagedPlacementPlan honoring saved positions over
/// NewItems fallback, resolveDestination anchor lookup with fallback,
/// and boundaryDestination semantics across sections.
final class LayoutReconcilerTests: XCTestCase {
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
    func testUnmanagedPlanFavorsSavedPosition() {
        let desired = DesiredLayout.fromSavedSectionOrder(
            ["visible": ["com.known.app:Status"]],
            newItemsPlacement: placement(section: "hidden")
        )

        let result = LayoutReconciler.unmanagedPlacementPlan(
            desired: desired,
            unmanagedUIDs: ["com.known.app:Status"],
            currentUIDs: ["com.known.app:Status"]
        )

        XCTAssertEqual(
            result["com.known.app:Status"],
            .saved(section: .visible, index: 0)
        )
    }

    /// An unmanaged uid with no saved position falls back to
    /// .newItemDefault using the DesiredLayout's NewItemsPlacement.
    func testUnmanagedPlanFallsBackToNewItemDefault() {
        let desired = DesiredLayout.fromSavedSectionOrder(
            [:],
            newItemsPlacement: placement(section: "hidden")
        )

        let result = LayoutReconciler.unmanagedPlacementPlan(
            desired: desired,
            unmanagedUIDs: ["com.new.app:Status"],
            currentUIDs: ["com.new.app:Status"]
        )

        XCTAssertEqual(
            result["com.new.app:Status"],
            .newItemDefault(section: .hidden)
        )
    }

    // MARK: - resolveDestination

    /// .leftOfUID with an anchor present in items resolves to
    /// .leftOfItem(anchor).
    func testResolveDestinationLeftOfPresentAnchor() {
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

        XCTAssertEqual(result, .leftOfItem(anchor))
    }

    /// .rightOfUID with anchor present resolves to .rightOfItem(anchor).
    func testResolveDestinationRightOfPresentAnchor() {
        let anchor = item(bundleID: "com.anchor.app", title: "Anchor", windowID: 9002)

        let result = LayoutReconciler.resolveDestination(
            .rightOfUID("com.anchor.app:Anchor"),
            items: [anchor],
            controlItems: MenuBarItemManager.ControlItemPair.fixture(
                hiddenAt: CGRect(x: 400, y: 0, width: 10, height: 22)
            ),
            fallbackSection: .visible
        )

        XCTAssertEqual(result, .rightOfItem(anchor))
    }

    /// When the named anchor uid has disappeared, fall back to the
    /// section boundary for the supplied fallback section.
    func testResolveDestinationFallsBackToSectionBoundaryWhenAnchorMissing() {
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
        XCTAssertEqual(result, .leftOfItem(pair.hidden))
    }

    /// .sectionBoundary is resolved directly via boundaryDestination,
    /// independent of the fallbackSection argument.
    func testResolveDestinationSectionBoundaryUsesGivenSection() {
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

        XCTAssertEqual(result, .leftOfItem(pair.alwaysHidden!))
    }

    // MARK: - boundaryDestination

    /// .visible boundary places the item to the right of the hidden
    /// control item (which is the leftmost-visible insertion point).
    func testBoundaryDestinationVisible() {
        let pair = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: CGRect(x: 400, y: 0, width: 10, height: 22)
        )

        let result = LayoutReconciler.boundaryDestination(
            for: .visible,
            controlItems: pair
        )

        XCTAssertEqual(result, .rightOfItem(pair.hidden))
    }

    /// .hidden boundary places the item to the left of the hidden
    /// control item.
    func testBoundaryDestinationHidden() {
        let pair = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: CGRect(x: 400, y: 0, width: 10, height: 22)
        )

        let result = LayoutReconciler.boundaryDestination(
            for: .hidden,
            controlItems: pair
        )

        XCTAssertEqual(result, .leftOfItem(pair.hidden))
    }

    /// .alwaysHidden boundary places the item to the left of the
    /// always-hidden control item when present.
    func testBoundaryDestinationAlwaysHiddenWithControl() {
        let pair = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: CGRect(x: 400, y: 0, width: 10, height: 22),
            alwaysHiddenAt: CGRect(x: 200, y: 0, width: 10, height: 22)
        )

        let result = LayoutReconciler.boundaryDestination(
            for: .alwaysHidden,
            controlItems: pair
        )

        XCTAssertEqual(result, .leftOfItem(pair.alwaysHidden!))
    }

    /// .alwaysHidden boundary falls back to the hidden control item
    /// when the always-hidden control is absent (section disabled).
    func testBoundaryDestinationAlwaysHiddenWithoutControl() {
        let pair = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: CGRect(x: 400, y: 0, width: 10, height: 22)
        )

        let result = LayoutReconciler.boundaryDestination(
            for: .alwaysHidden,
            controlItems: pair
        )

        XCTAssertEqual(result, .leftOfItem(pair.hidden))
    }

    /// NewItemsPlacement with an anchor present in currentUIDs yields
    /// .newItemAnchored.
    func testUnmanagedPlanUsesNewItemsAnchorWhenPresent() {
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

        XCTAssertEqual(
            result["com.new.app:Status"],
            .newItemAnchored(
                section: .visible,
                anchorUID: "com.spotlight.app:Anchor",
                relation: .leftOfAnchor
            )
        )
    }
}
