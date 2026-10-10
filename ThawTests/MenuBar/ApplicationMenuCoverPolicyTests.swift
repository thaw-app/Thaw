//
//  ApplicationMenuCoverPolicyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Cover only the desktop, not working Finder windows, and never cover the Apple menu, which has no alternate route.
/// Screenshots cannot verify these focus and geometry decisions after the fact.
@Suite("Application menu cover policy")
struct ApplicationMenuCoverPolicyTests {
    // MARK: Fixtures

    /// Live frame shape: top-left origin, 30 pt height, with adjacent titles overlapping by 1 pt.
    private static func title(
        _ role: String? = "AXMenuBarItem",
        x: CGFloat,
        width: CGFloat
    ) -> MenuBarTitleFrame {
        MenuBarTitleFrame(role: role, frame: CGRect(x: x, y: 0, width: width, height: 30))
    }

    private static let apple = title(x: 10, width: 34)
    private static let finder = title(x: 43, width: 55)
    private static let file = title(x: 97, width: 40)

    // MARK: Focus classification

    @Test("Another app frontmost is not the desktop")
    func otherAppIsNotFinder() {
        let state = DesktopFocusState.classify(
            frontmostBundleIdentifier: "com.apple.Safari",
            hasFocusedWindow: true,
            focusedWindowSubrole: "AXStandardWindow"
        )
        #expect(state == .notFinder)
    }

    @Test("An unidentifiable frontmost app is not the desktop")
    func missingBundleIdentifierIsNotFinder() {
        let state = DesktopFocusState.classify(
            frontmostBundleIdentifier: nil,
            hasFocusedWindow: false,
            focusedWindowSubrole: nil
        )
        #expect(state == .notFinder)
    }

    @Test("Finder frontmost with nothing focused is the desktop")
    func finderWithoutFocusedWindowIsDesktop() {
        let state = DesktopFocusState.classify(
            frontmostBundleIdentifier: "com.apple.finder",
            hasFocusedWindow: false,
            focusedWindowSubrole: nil
        )
        #expect(state == .desktop)
    }

    @Test("Finder focused on the desktop window is the desktop")
    func finderFocusedOnDesktopSubroleIsDesktop() {
        let state = DesktopFocusState.classify(
            frontmostBundleIdentifier: "com.apple.finder",
            hasFocusedWindow: true,
            focusedWindowSubrole: "AXDesktop"
        )
        #expect(state == .desktop)
    }

    @Test("A real Finder window keeps its menus")
    func finderWindowIsNotDesktop() {
        let state = DesktopFocusState.classify(
            frontmostBundleIdentifier: "com.apple.finder",
            hasFocusedWindow: true,
            focusedWindowSubrole: "AXStandardWindow"
        )
        #expect(state == .window)
    }

    /// An unreadable subrole still means a window; hiding working menus is worse than missing the desktop.
    @Test("A focused window with no readable subrole is treated as a window")
    func unreadableSubroleIsWindow() {
        let state = DesktopFocusState.classify(
            frontmostBundleIdentifier: "com.apple.finder",
            hasFocusedWindow: true,
            focusedWindowSubrole: nil
        )
        #expect(state == .window)
    }

    @Test("Only the desktop is covered")
    func onlyDesktopIsCovered() {
        #expect(ApplicationMenuCoverPolicy.shouldCover(.desktop))
        #expect(!ApplicationMenuCoverPolicy.shouldCover(.window))
        #expect(!ApplicationMenuCoverPolicy.shouldCover(.notFinder))
    }

    // MARK: Cover geometry

    @Test("The cover spans the application menus and stops at the Apple menu")
    func coverSpansApplicationMenus() throws {
        let rect = try #require(
            ApplicationMenuCoverPolicy.coverRect(forOrderedTitles: [Self.apple, Self.finder, Self.file])
        )
        #expect(rect.minX == 44)
        #expect(rect.maxX == 137)
        #expect(rect.minY == 0)
        #expect(rect.height == 30)
    }

    /// Adjacent titles overlap; a naive union starts at 43 inside the Apple menu ending at 44.
    @Test("The overlapping point between Apple and the first menu is not covered")
    func overlapDoesNotClipTheAppleMenu() throws {
        let rect = try #require(
            ApplicationMenuCoverPolicy.coverRect(forOrderedTitles: [Self.apple, Self.finder])
        )
        #expect(rect.minX == Self.apple.frame.maxX)
    }

    @Test("A bar with only the Apple menu has nothing to cover")
    func appleMenuAloneIsNotCovered() {
        #expect(ApplicationMenuCoverPolicy.coverRect(forOrderedTitles: [Self.apple]) == nil)
    }

    @Test("An empty menu bar has nothing to cover")
    func emptyBarIsNotCovered() {
        #expect(ApplicationMenuCoverPolicy.coverRect(forOrderedTitles: []) == nil)
    }

    /// Status hosts share menu bar children but are not menus; covering them would obscure icons.
    @Test("Non-menu children are excluded from the cover")
    func nonMenuChildrenAreExcluded() throws {
        let statusItem = Self.title("AXMenuExtra", x: 1400, width: 30)
        let rect = try #require(
            ApplicationMenuCoverPolicy.coverRect(
                forOrderedTitles: [Self.apple, Self.finder, statusItem]
            )
        )
        #expect(rect.maxX == Self.finder.frame.maxX)
    }

    @Test("A child with no readable role is excluded")
    func rolelessChildIsExcluded() {
        let roleless = Self.title(nil, x: 43, width: 55)
        #expect(ApplicationMenuCoverPolicy.coverRect(forOrderedTitles: [Self.apple, roleless]) == nil)
    }

    /// During rebuild only Apple may have a real frame; do not strand a cover over empty menus.
    @Test("Zero-width menus produce no cover")
    func zeroWidthMenusProduceNoCover() {
        let empty = Self.title(x: 44, width: 0)
        #expect(ApplicationMenuCoverPolicy.coverRect(forOrderedTitles: [Self.apple, empty]) == nil)
    }

    @Test("A menu entirely behind the Apple menu produces no cover")
    func menuBehindAppleProducesNoCover() {
        let stale = Self.title(x: 10, width: 20)
        #expect(ApplicationMenuCoverPolicy.coverRect(forOrderedTitles: [Self.apple, stale]) == nil)
    }
}
