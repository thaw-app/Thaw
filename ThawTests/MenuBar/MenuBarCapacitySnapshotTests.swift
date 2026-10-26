//
//  MenuBarCapacitySnapshotTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Application menus wrapping past the notch collapse the trailing status-item lane; automatic drags must decline.
@Suite("Menu bar capacity snapshot")
struct MenuBarCapacitySnapshotTests {
    /// A 1352-point-wide scaled MacBook display with a 160-point notch.
    private let display = CGRect(x: 0, y: 0, width: 1352, height: 878)
    private let notch = CGRect(x: 596, y: 0, width: 160, height: 32)
    private let controlCenterMinX: CGFloat = 1300

    private func snapshot(notch: CGRect?, menu: CGRect?) -> MenuBarCapacitySnapshot {
        MenuBarCapacitySnapshot(
            displayID: 1,
            displayBounds: display,
            notchFrame: notch,
            applicationMenuFrame: menu,
            trailingBoundary: controlCenterMinX,
            overflowControlBounds: []
        )
    }

    private func menu(width: CGFloat) -> CGRect {
        CGRect(x: 0, y: 0, width: width, height: 24)
    }

    @Test("A menu that ends left of the notch does not wrap")
    func menuLeftOfNotchDoesNotWrap() {
        #expect(!snapshot(notch: notch, menu: menu(width: 500)).applicationMenuWrapsPastNotch)
    }

    @Test("A menu that ends exactly at the notch's right edge does not wrap")
    func menuEndingAtNotchEdgeDoesNotWrap() {
        #expect(!snapshot(notch: notch, menu: menu(width: notch.maxX)).applicationMenuWrapsPastNotch)
    }

    @Test("A menu whose last title sits right of the notch wraps")
    func menuPastNotchWraps() {
        #expect(snapshot(notch: notch, menu: menu(width: 840)).applicationMenuWrapsPastNotch)
    }

    @Test("Without a notch nothing wraps, however long the menu")
    func noNotchNeverWraps() {
        #expect(!snapshot(notch: nil, menu: menu(width: 1000)).applicationMenuWrapsPastNotch)
    }

    @Test("Without a measured menu nothing wraps")
    func noMenuNeverWraps() {
        #expect(!snapshot(notch: notch, menu: nil).applicationMenuWrapsPastNotch)
        #expect(!snapshot(notch: notch, menu: .zero).applicationMenuWrapsPastNotch)
    }

    @Test("A wrapped menu shortens the trailing lane to what lies right of its last title")
    func wrappedMenuShortensTrailingLane() {
        let unwrapped = snapshot(notch: notch, menu: menu(width: 500))
            .availableWidth(applicationMenus: .visible)
        let wrapped = snapshot(notch: notch, menu: menu(width: 840))
            .availableWidth(applicationMenus: .visible)

        // Unwrapped, the lane starts at the notch's right clearance.
        #expect(unwrapped == controlCenterMinX - (notch.maxX + MenuBarCapacitySnapshot.notchGap))
        // Wrapped, it starts where the last menu title ends.
        #expect(wrapped == controlCenterMinX - 840)
    }

    @Test("A reveal that fits stays inline; one that overflows falls back to the Thaw Bar")
    func inlineOverflowDecision() {
        let capacity = snapshot(notch: nil, menu: menu(width: 400))
        let free = capacity.availableWidth(applicationMenus: .visible) ?? 0
        #expect(!MenuBarSection.overflowsInline(
            totalItemsWidth: free - 1, capacity: capacity, allowHidingApplicationMenus: false
        ))
        #expect(MenuBarSection.overflowsInline(
            totalItemsWidth: free + 1, capacity: capacity, allowHidingApplicationMenus: false
        ))
        // Hiding the app menus frees their width.
        #expect(!MenuBarSection.overflowsInline(
            totalItemsWidth: free + 1, capacity: capacity, allowHidingApplicationMenus: true
        ))
    }

    @Test("Beside a notch only the lane right of it holds status items, however short the menus", arguments: [false, true])
    func notchRevealCountsOnlyTheRightLane(allowHidingApplicationMenus: Bool) {
        let capacity = snapshot(notch: notch, menu: menu(width: 200))
        let rightLane = controlCenterMinX - (notch.maxX + MenuBarCapacitySnapshot.notchGap)
        // Wider than the right lane, narrower than both lanes together: macOS puts the rest behind ».
        let tooWide = rightLane + 80

        #expect(MenuBarSection.overflowsInline(
            totalItemsWidth: tooWide, capacity: capacity, allowHidingApplicationMenus: allowHidingApplicationMenus
        ))
        #expect(MenuBarSection.presentationMode(
            totalItemsWidth: tooWide, capacity: capacity, allowHidingApplicationMenus: allowHidingApplicationMenus
        ) == .thawBar)
        #expect(MenuBarSection.presentationMode(
            totalItemsWidth: rightLane - 1, capacity: capacity, allowHidingApplicationMenus: allowHidingApplicationMenus
        ) == .inline)
    }

    @Test("Unknown free width never forces the Thaw Bar")
    func unknownCapacityStaysInline() {
        let capacity = MenuBarCapacitySnapshot(
            displayID: 1,
            displayBounds: display,
            notchFrame: nil,
            applicationMenuFrame: nil,
            trailingBoundary: nil,
            overflowControlBounds: []
        )
        #expect(!MenuBarSection.overflowsInline(
            totalItemsWidth: 10000, capacity: capacity, allowHidingApplicationMenus: false
        ))
    }
}
