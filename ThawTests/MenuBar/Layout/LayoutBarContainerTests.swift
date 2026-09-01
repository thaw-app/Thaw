//
//  LayoutBarContainerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Testing
@testable import Thaw

@MainActor
@Suite("Badge-only layout section drops")
struct LayoutBarContainerTests {
    @Test("A regular item sees a badge-only section as an empty drop target")
    func badgeOnlySectionHasNoRegularItemDropTargets() {
        let badge = LayoutBarNewItemsBadgeView()

        let regularItemTargets = LayoutBarContainer.enabledDropTargets(
            in: [badge],
            excludingBadge: true
        )
        let badgeDragTargets = LayoutBarContainer.enabledDropTargets(
            in: [badge],
            excludingBadge: false
        )

        #expect(regularItemTargets.isEmpty)
        #expect(badgeDragTargets.count == 1)
        #expect(badgeDragTargets.first === badge)
    }

    @Test("A regular item lands on the side of the badge where it is dropped")
    func badgeOnlyInsertionIndexUsesDropSideOfBadge() {
        let badge = LayoutBarNewItemsBadgeView()
        badge.setFrameOrigin(CGPoint(x: 100, y: 0))

        let beforeBadgeIndex = LayoutBarContainer.emptyTargetInsertionIndex(
            for: badge.frame.midX - 1,
            in: [badge],
            excludingBadge: true
        )
        let afterBadgeIndex = LayoutBarContainer.emptyTargetInsertionIndex(
            for: badge.frame.midX + 1,
            in: [badge],
            excludingBadge: true
        )

        #expect(beforeBadgeIndex == 0)
        #expect(afterBadgeIndex == 1)
    }

    @Test("An empty section inserts its first item at the beginning")
    func emptySectionInsertionIndexStartsAtBeginning() {
        let insertionIndex = LayoutBarContainer.emptyTargetInsertionIndex(
            for: 500,
            in: [],
            excludingBadge: true
        )

        #expect(insertionIndex == 0)
    }
}

@Suite("Layout item activation")
struct LayoutBarItemActivationTests {
    @Test("A left click released inside the icon activates its menu bar item")
    func leftClickActivates() {
        #expect(LayoutBarItemView.shouldActivateRepresentedItem(
            buttonNumber: 0,
            didBeginDragging: false,
            mouseUpInsideBounds: true
        ))
    }

    @Test("A drag never activates the app on mouse-up")
    func dragDoesNotActivate() {
        #expect(!LayoutBarItemView.shouldActivateRepresentedItem(
            buttonNumber: 0,
            didBeginDragging: true,
            mouseUpInsideBounds: true
        ))
    }

    @Test("Clicks released outside the icon and non-left clicks do not activate")
    func unrelatedClicksDoNotActivate() {
        #expect(!LayoutBarItemView.shouldActivateRepresentedItem(
            buttonNumber: 0,
            didBeginDragging: false,
            mouseUpInsideBounds: false
        ))
        #expect(!LayoutBarItemView.shouldActivateRepresentedItem(
            buttonNumber: 1,
            didBeginDragging: false,
            mouseUpInsideBounds: true
        ))
    }
}

/// A cross-container drop only inserts the dragged view into the destination,
/// so the drag unit is resolved against both bars. The order those items are
/// handed over in is the order the block move commits, which is why the source
/// bar leads.
@Suite("Cross-container group drag ordering")
struct LayoutBarGroupResolutionOrderTests {
    private func item(_ bundleID: String, _ title: String, _ windowID: CGWindowID) -> MenuBarItem {
        .fixture(tag: .appItem(bundleID: bundleID, title: title), windowID: windowID)
    }

    @Test("A member dragged out of its group keeps its place in the source order")
    func draggedMemberKeepsSourceOrder() throws {
        let first = item("com.example.a", "1", 1)
        let dragged = item("com.example.a", "2", 2)
        let last = item("com.example.a", "3", 3)
        let unrelated = item("com.example.b", "1", 4)

        // The dragged item shows up in the destination and is restored to the
        // slot it left in the source before the unit is resolved.
        let resolutionItems = LayoutBarPaddingView.groupResolutionItems(
            sourceItems: [first, dragged, last],
            destinationItems: [unrelated, dragged]
        )
        let groups = MenuBarItemGroupResolver.resolve(
            tags: resolutionItems.map(\.tag),
            groupSet: .empty
        )
        let draggedIndex = try #require(resolutionItems.firstIndex { $0.tag == dragged.tag })
        let unit = MenuBarItemGroupResolver
            .dragUnitIndices(forIndex: draggedIndex, in: groups)
            .map { resolutionItems[$0].tag }

        #expect(unit == [first.tag, dragged.tag, last.tag])
    }

    @Test("A member already sitting in the destination still joins the unit")
    func destinationMemberJoinsTheUnit() throws {
        let first = item("com.example.a", "1", 1)
        let dragged = item("com.example.a", "2", 2)
        let stranded = item("com.example.a", "3", 3)
        let unrelated = item("com.example.b", "1", 4)

        let resolutionItems = LayoutBarPaddingView.groupResolutionItems(
            sourceItems: [first, dragged],
            destinationItems: [unrelated, dragged, stranded]
        )
        let groups = MenuBarItemGroupResolver.resolve(
            tags: resolutionItems.map(\.tag),
            groupSet: .empty
        )
        let draggedIndex = try #require(resolutionItems.firstIndex { $0.tag == dragged.tag })
        let unit = MenuBarItemGroupResolver
            .dragUnitIndices(forIndex: draggedIndex, in: groups)
            .map { resolutionItems[$0].tag }

        #expect(resolutionItems.map(\.tag) == [first.tag, dragged.tag, unrelated.tag, stranded.tag])
        #expect(unit == [first.tag, dragged.tag, stranded.tag])
    }
}
