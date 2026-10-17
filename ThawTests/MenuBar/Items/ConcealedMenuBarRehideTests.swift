//
//  ConcealedMenuBarRehideTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Covers ``MenuBarItemManager/menuBarAppearsConcealed(itemBounds:itemIsOnScreen:hiddenDividerMaxX:displayBounds:)``.
///
/// With the menu bar auto-hidden, every item window reports off screen. The
/// rehide then failed nine times as "stale destination" in about 35 seconds and
/// marked the item waitForRelaunch, so it stayed in the visible section until
/// its app relaunched. Positions below are from a recording of that case on a
/// MacBook built-in display (1800x1169).
@Suite("Concealed menu bar rehide")
struct ConcealedMenuBarRehideTests {
    private let display = [CGRect(x: 0, y: 0, width: 1800, height: 1169)]
    /// The hidden divider at x -3832, 5020 wide.
    private let dividerMaxX: CGFloat = 1188
    /// TG Pro after the temporary show, left of the chevron.
    private let shownItem = CGRect(x: 1322, y: 0, width: 83, height: 24)

    @Test("A shown item reading off screen at the top of the display means the bar is hidden")
    func offScreenShownItemMeansHiddenBar() {
        #expect(MenuBarItemManager.menuBarAppearsConcealed(
            itemBounds: shownItem,
            itemIsOnScreen: false,
            hiddenDividerMaxX: dividerMaxX,
            displayBounds: display
        ))
    }

    @Test("A bar slid up above the display in full screen still counts as hidden")
    func slidUpBarCountsAsHidden() {
        #expect(MenuBarItemManager.menuBarAppearsConcealed(
            itemBounds: shownItem.offsetBy(dx: 0, dy: -62),
            itemIsOnScreen: false,
            hiddenDividerMaxX: dividerMaxX,
            displayBounds: display
        ))
    }

    @Test("An item that reads on screen is not behind a hidden bar")
    func onScreenItemIsNotConcealed() {
        #expect(!MenuBarItemManager.menuBarAppearsConcealed(
            itemBounds: shownItem,
            itemIsOnScreen: true,
            hiddenDividerMaxX: dividerMaxX,
            displayBounds: display
        ))
    }

    @Test("A parked item left of the divider is not taken for a hidden bar")
    func parkedItemIsNotConcealed() {
        #expect(!MenuBarItemManager.menuBarAppearsConcealed(
            itemBounds: CGRect(x: -4029, y: 0, width: 51, height: 24),
            itemIsOnScreen: false,
            hiddenDividerMaxX: dividerMaxX,
            displayBounds: display
        ))
    }

    @Test("An item away from the top of every display stays a normal failure")
    func itemOffTheBarIsNotConcealed() {
        #expect(!MenuBarItemManager.menuBarAppearsConcealed(
            itemBounds: shownItem.offsetBy(dx: 0, dy: 600),
            itemIsOnScreen: false,
            hiddenDividerMaxX: dividerMaxX,
            displayBounds: display
        ))
    }

    @Test("Without a divider reading there is nothing to compare against")
    func missingDividerIsNotConcealed() {
        #expect(!MenuBarItemManager.menuBarAppearsConcealed(
            itemBounds: shownItem,
            itemIsOnScreen: false,
            hiddenDividerMaxX: nil,
            displayBounds: display
        ))
    }

    // MARK: Retry timer

    /// temporarilyShow cancels the timer before its forced rehide and can
    /// return before arming it again, so a deferred item needs the timer here.
    @Test("A forced rehide that deferred an item re-arms the timer")
    func forcedDeferralRearmsTimer() {
        #expect(MenuBarItemManager.rearmsRehideTimer(force: true, deferredBehindHiddenMenuBar: true))
    }

    @Test("A forced rehide with ordinary failures leaves the timer to its caller")
    func forcedFailureLeavesTimerToCaller() {
        #expect(!MenuBarItemManager.rearmsRehideTimer(force: true, deferredBehindHiddenMenuBar: false))
    }

    @Test("An unforced rehide always re-arms the timer for queued items")
    func unforcedRehideRearmsTimer() {
        #expect(MenuBarItemManager.rearmsRehideTimer(force: false, deferredBehindHiddenMenuBar: false))
        #expect(MenuBarItemManager.rearmsRehideTimer(force: false, deferredBehindHiddenMenuBar: true))
    }
}
