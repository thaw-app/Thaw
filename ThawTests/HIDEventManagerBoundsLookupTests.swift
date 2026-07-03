//
//  HIDEventManagerBoundsLookupTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw
import XCTest

final class HIDEventManagerBoundsLookupTests: XCTestCase {
    func testBoundsLookupTrustsCachedBoundsOnMacOS27Path() {
        let syntheticWindowID: CGWindowID = 9_000_001
        let clockBounds = CGRect(x: 1180, y: 0, width: 140, height: 22)
        let entries = [(windowID: syntheticWindowID, bounds: clockBounds)]
        let clickPoint = CGPoint(x: clockBounds.midX, y: clockBounds.midY)

        XCTAssertTrue(
            HIDEventManager.menuBarBoundsLookupContains(
                clickPoint,
                entries: entries,
                trustCachedBoundsWithoutLiveWindowVerification: true,
                liveWindowBounds: { _ in nil }
            )
        )
    }

    func testBoundsLookupRequiresLiveWindowBoundsOnLegacyPath() {
        let windowID: CGWindowID = 42
        let bounds = CGRect(x: 100, y: 0, width: 24, height: 22)
        let entries = [(windowID: windowID, bounds: bounds)]
        let clickPoint = CGPoint(x: bounds.midX, y: bounds.midY)

        XCTAssertFalse(
            HIDEventManager.menuBarBoundsLookupContains(
                clickPoint,
                entries: entries,
                trustCachedBoundsWithoutLiveWindowVerification: false,
                liveWindowBounds: { _ in nil }
            )
        )

        XCTAssertTrue(
            HIDEventManager.menuBarBoundsLookupContains(
                clickPoint,
                entries: entries,
                trustCachedBoundsWithoutLiveWindowVerification: false,
                liveWindowBounds: { id in
                    id == windowID ? bounds : nil
                }
            )
        )
    }

    func testShouldIncludeClockInVisibleSection() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarAgent bounds policy is macOS 27-specific")
        }

        let clock = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.clock"),
            windowID: 9_000_002,
            bounds: CGRect(x: 1180, y: 0, width: 140, height: 22)
        )

        XCTAssertTrue(
            HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(clock, section: .visible)
        )
    }

    func testShouldExcludeNativeOverflowPlaceholder() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("Native overflow placeholders are macOS 27-specific")
        }

        let overflow = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "<<"),
            windowID: 9_000_003,
            bounds: CGRect(x: 900, y: 0, width: 18, height: 22)
        )

        XCTAssertFalse(
            HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(overflow, section: .visible)
        )
    }

    func testShouldExcludeConcealedHiddenItemsButKeepClock() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarAgent bounds policy is macOS 27-specific")
        }

        let hiddenApp = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status"),
            windowID: 9_000_004,
            bounds: CGRect(x: 500, y: 0, width: 24, height: 22)
        )
        let clock = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.clock"),
            windowID: 9_000_005,
            bounds: CGRect(x: 1180, y: 0, width: 140, height: 22)
        )

        XCTAssertFalse(
            HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(hiddenApp, section: .hidden)
        )
        XCTAssertTrue(
            HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(clock, section: .visible)
        )
    }

    func testShouldExcludePhantomFramesBelowMenuBar() {
        let phantom = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status"),
            windowID: 9_000_006,
            bounds: CGRect(x: 500, y: 1400, width: 24, height: 22)
        )

        XCTAssertFalse(
            HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(phantom, section: .visible)
        )
    }

    // MARK: - Bounds cache surviving a section toggle

    /// Mirrors the filter applied by `HIDEventManager.rebuildWindowBoundsLookup(from:)`
    /// so the toggle-survival invariant can be asserted without an AppState:
    /// the resulting bounds lookup must stay non-empty across a hidden-section
    /// show/hide transition, and concealed app items must never trap a click.
    private func filteredEntries(
        for items: [MenuBarItem],
        sectionForItem: (MenuBarItem) -> MenuBarSection.Name?
    ) -> [(windowID: CGWindowID, bounds: CGRect)] {
        items.compactMap { item in
            guard HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(
                item,
                section: sectionForItem(item)
            ) else {
                return nil
            }
            return (windowID: item.windowID, bounds: item.bounds)
        }
    }

    /// Before a toggle, both the Clock and a third-party app item in the visible
    /// section participate in show-on hit-testing.
    func testBoundsLookupNonEmptyBeforeToggle() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarAgent bounds policy is macOS 27-specific")
        }

        let clock = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.clock"),
            windowID: 9_000_010,
            bounds: CGRect(x: 1180, y: 0, width: 140, height: 22)
        )
        let app = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status"),
            windowID: 9_000_011,
            bounds: CGRect(x: 1000, y: 0, width: 24, height: 22)
        )

        let entries = filteredEntries(for: [clock, app]) { _ in .visible }

        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.contains { $0.windowID == clock.windowID })
        XCTAssertTrue(entries.contains { $0.windowID == app.windowID })
    }

    /// After a hidden-section toggle, the Clock (a non-concealable system item)
    /// stays in the lookup so the cache is never wiped to empty on macOS 27,
    /// while the now-concealed third-party app item drops out so it cannot
    /// trap a click as empty space. This is the regression that previously
    /// let show-on-click fire on top of the Clock.
    func testBoundsLookupSurvivesHiddenSectionToggle() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("MenuBarAgent bounds policy is macOS 27-specific")
        }

        let clock = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.clock"),
            windowID: 9_000_010,
            bounds: CGRect(x: 1180, y: 0, width: 140, height: 22)
        )
        let app = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status"),
            windowID: 9_000_011,
            bounds: CGRect(x: 1000, y: 0, width: 24, height: 22)
        )

        // Simulate the section assignment the hider would report after the
        // hidden section is shown and then hidden again: the app item is
        // concealed (section .hidden), the Clock is non-concealable so its
        // reported section is irrelevant to inclusion.
        let entriesAfterHide = filteredEntries(for: [clock, app]) { item in
            item.tag.isNonConcealableSystemItem ? .visible : .hidden
        }

        XCTAssertFalse(entriesAfterHide.isEmpty, "bounds lookup must stay non-empty across a section toggle on macOS 27")
        XCTAssertTrue(entriesAfterHide.contains { $0.windowID == clock.windowID })
        XCTAssertFalse(entriesAfterHide.contains { $0.windowID == app.windowID })

        // And clicking on the concealed app item's former location must not be
        // reported as empty space now that its bounds are out of the lookup.
        let clickOverApp = CGPoint(x: 1000, y: 0)
        XCTAssertFalse(
            HIDEventManager.menuBarBoundsLookupContains(
                clickOverApp,
                entries: entriesAfterHide,
                trustCachedBoundsWithoutLiveWindowVerification: true,
                liveWindowBounds: { _ in nil }
            )
        )
    }

    /// A concealed app item whose AX frame is a phantom (midY below the menu
    /// bar) is excluded from the lookup even when it is nominally assigned to
    /// the visible section, so phantom frames that survive a transition can
    /// never trap a click.
    func testPhantomFrameExcludedEvenWhenSectionVisible() {
        let phantom = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status"),
            windowID: 9_000_012,
            bounds: CGRect(x: 1000, y: 1400, width: 24, height: 22)
        )

        XCTAssertFalse(
            HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(phantom, section: .visible)
        )
    }

    func testBoundsLookupEntriesIncludeRecentUnmanagedOnScreenItems() {
        let knownManaged = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.stonerl.Thaw", title: "Thaw"),
            windowID: 9_000_020,
            bounds: CGRect(x: 1120, y: 0, width: 24, height: 22)
        )
        let unmanagedStatusItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.other", title: "Other"),
            windowID: 9_000_021,
            bounds: CGRect(x: 1160, y: 0, width: 24, height: 22)
        )

        let entries = HIDEventManager.menuBarItemBoundsLookupEntries(
            from: [knownManaged, unmanagedStatusItem],
            excluding: [knownManaged.windowID],
            shouldInclude: { item in
                HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(item, section: nil)
            }
        )

        XCTAssertFalse(entries.contains { $0.windowID == knownManaged.windowID })
        XCTAssertTrue(entries.contains { $0.windowID == unmanagedStatusItem.windowID })
        XCTAssertTrue(
            HIDEventManager.menuBarBoundsLookupContains(
                CGPoint(x: unmanagedStatusItem.bounds.midX, y: unmanagedStatusItem.bounds.midY),
                entries: entries,
                trustCachedBoundsWithoutLiveWindowVerification: true,
                liveWindowBounds: { _ in nil }
            )
        )
    }
}
