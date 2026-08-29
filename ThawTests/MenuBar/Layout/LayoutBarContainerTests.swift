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
