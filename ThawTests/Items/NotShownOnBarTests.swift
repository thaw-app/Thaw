//
//  NotShownOnBarTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// Geometry identifies items assigned Visible that macOS is not drawing.
@MainActor
struct NotShownOnBarTests {
    private static let screens = [
        CGRect(x: 0, y: 0, width: 2560, height: 1440),
        CGRect(x: 2560, y: 290, width: 1710, height: 1107),
    ]

    @Test("A lower bar's own seat is shown, but shared seats and frames below it are not")
    func lowerDisplaySeats() {
        let seated = item("A", x: 3600, y: 295, windowID: 1)
        let neighbour = item("B", x: 3630, y: 295, windowID: 2)
        let phantom = item("C", x: 3600, y: 295, windowID: 3)
        let parked = item("D", x: 3600, y: 1068, windowID: 4)
        #expect(!NotShownOnBar.looksNotShown(seated, among: [seated, neighbour], screens: Self.screens))
        #expect(NotShownOnBar.looksNotShown(seated, among: [seated, phantom], screens: Self.screens))
        #expect(NotShownOnBar.looksNotShown(parked, among: [parked], screens: Self.screens))
    }

    private func item(_ title: String, x: CGFloat, y: CGFloat = 3, width: CGFloat = 24, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: windowID,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: y, width: width, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("an item on a seat of its own is shown")
    func ownSeatIsShown() {
        let a = item("A", x: 1600, windowID: 1)
        let b = item("B", x: 1630, windowID: 2)
        #expect(!NotShownOnBar.looksNotShown(a, among: [a, b], screens: Self.screens))
    }

    @Test("an item reporting another item's seat is not shown")
    func sharedSeatIsNotShown() {
        let under = item("Under", x: 1747, width: 25, windowID: 1)
        let over = item("Over", x: 1745, width: 27, windowID: 2)
        #expect(NotShownOnBar.looksNotShown(under, among: [under, over], screens: Self.screens))
    }

    @Test("an item below the bar is not shown")
    func belowTheBarIsNotShown() {
        let lost = item("Lost", x: 1600, y: 1157, windowID: 1)
        #expect(NotShownOnBar.looksNotShown(lost, among: [lost], screens: Self.screens))
    }

    @Test("an item with no size is not shown")
    func zeroSizeIsNotShown() {
        let flat = item("Flat", x: 1600, width: 0, windowID: 1)
        #expect(NotShownOnBar.looksNotShown(flat, among: [flat], screens: Self.screens))
    }
}
