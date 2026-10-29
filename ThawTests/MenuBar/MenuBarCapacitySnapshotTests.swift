//
//  MenuBarCapacitySnapshotTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
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

    private func plain(
        trailing: CGFloat? = 1300,
        notch: CGRect? = nil,
        overflow: [CGRect] = []
    ) -> MenuBarCapacitySnapshot {
        MenuBarCapacitySnapshot(
            displayID: 1,
            displayBounds: display,
            notchFrame: notch,
            applicationMenuFrame: menu(width: 300),
            trailingBoundary: trailing,
            overflowControlBounds: overflow
        )
    }

    private func bar(_ minX: CGFloat, _ maxX: CGFloat) -> CGRect {
        CGRect(x: minX, y: 4, width: maxX - minX, height: 16)
    }

    @Test("Reserved spans are clipped to the lane and counted once where they overlap")
    func reservationsMerge() {
        let snapshot = plain()
        // The lane runs from the menus' end at 300 to Control Center at 1300.
        #expect(snapshot.availableWidth(applicationMenus: .visible) == 1000)
        #expect(snapshot.availableWidth(applicationMenus: .hidden) == 1300)

        let overlapping = [bar(400, 500), bar(450, 600), bar(450, 520)]
        #expect(snapshot.availableWidth(applicationMenus: .visible, reserving: overlapping) == 800)

        let apart = [bar(400, 500), bar(700, 750)]
        #expect(snapshot.availableWidth(applicationMenus: .visible, reserving: apart) == 850)

        let clipped = [bar(200, 350), bar(1250, 1400)]
        #expect(snapshot.availableWidth(applicationMenus: .visible, reserving: clipped) == 900, "only the parts inside the lane count")

        let ignored = [CGRect.null, .zero, bar(100, 200), CGRect(x: 2000, y: 4, width: 50, height: 16)]
        #expect(snapshot.availableWidth(applicationMenus: .visible, reserving: ignored) == 1000)
    }

    @Test("The native overflow control is reserved like any other item")
    func overflowControlReserved() {
        let snapshot = plain(overflow: [bar(1200, 1230)])
        #expect(snapshot.availableWidth(applicationMenus: .visible) == 970)
        #expect(snapshot.availableWidth(applicationMenus: .visible, reserving: [bar(1210, 1240)]) == 960)
    }

    @Test("No width is known without a usable trailing boundary, menu frame or notch")
    func unknownWidth() {
        #expect(plain(trailing: nil).availableWidth(applicationMenus: .hidden) == nil)
        #expect(plain(trailing: 0).availableWidth(applicationMenus: .hidden) == nil)
        #expect(plain(trailing: 2000).availableWidth(applicationMenus: .hidden) == nil)
        #expect(plain(trailing: .infinity).availableWidth(applicationMenus: .hidden) == nil)
        #expect(plain(notch: .zero).availableWidth(applicationMenus: .hidden) == nil)
        #expect(snapshot(notch: nil, menu: nil).availableWidth(applicationMenus: .visible) == nil)
        #expect(snapshot(notch: nil, menu: nil).availableWidth(applicationMenus: .hidden) == 1300)
    }

    @Test("A snapshot of a real screen covers that display and finds its trailing boundary")
    @MainActor
    func captureRealScreen() throws {
        let screen = try #require(NSScreen.screens.first)
        let bounds = CGDisplayBounds(screen.displayID)
        let empty = MenuBarCapacitySnapshot.capture(on: screen, items: [])
        #expect(empty.displayID == screen.displayID)
        #expect(empty.displayBounds == bounds)
        #expect(empty.trailingBoundary == bounds.maxX, "with no Control Center the display's edge bounds the lane")
        #expect(empty.notchFrame == screen.frameOfNotch)
        if screen.frameOfNotch == nil {
            #expect(!MenuBarCapacitySnapshot.applicationMenuWrapsPastNotch(on: screen))
        }
    }
}
