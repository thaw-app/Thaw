//
//  ImmovabilityReasonTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Characterizes the gate that refuses to move an item, and its agreement
/// with `isMovable`.
///
/// The refusal sites log the named reason and the alert copy branches on it,
/// so a static macOS prohibition reads differently from a resolution failure (#905).
@Suite("Menu bar item immovability reason")
struct ImmovabilityReasonTests {
    /// An ordinary third-party item with a resolved source is movable and
    /// names no gate.
    @Test("A resolved app item is movable with no reason")
    func resolvedAppItemIsMovable() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.getdropbox.dropbox", title: "Item-0"),
            windowID: 100
        )
        #expect(item.immovabilityReason == nil)
        #expect(item.isMovable)
    }

    /// The static system items macOS refuses to move.
    @Test("Static system items name the prohibition", arguments: [
        MenuBarItemTag.clock,
        MenuBarItemTag.controlCenter,
        MenuBarItemTag.ssMenuAgent,
    ])
    func staticSystemItemsAreProhibited(tag: MenuBarItemTag) {
        let item = MenuBarItem.fixture(tag: tag, windowID: 101)
        #expect(item.immovabilityReason == .prohibitedSystemItem)
        #expect(!item.isMovable)
    }

    /// A generic Control Center slot whose source never resolved has an
    /// unknown owner, so the item is parked.
    @Test("An unresolved Control Center placeholder names the resolution gap")
    func unresolvedPlaceholderIsParked() {
        let item = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "Item-0"),
            windowID: 102,
            sourcePID: nil
        )
        #expect(item.immovabilityReason == .unresolvedControlCenterPlaceholder)
        #expect(!item.isMovable)
    }

    /// The same slot with a resolved source is a live transient module and
    /// moves normally.
    @Test("A resolved Control Center generic item is movable")
    func resolvedGenericItemIsMovable() {
        let item = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "Item-0"),
            windowID: 103,
            sourcePID: 500
        )
        #expect(item.immovabilityReason == nil)
        #expect(item.isMovable)
    }

    /// Only the `Item-N` shape marks a system-owned slot, even while the
    /// source is unresolved.
    @Test("An unresolved named Control Center title is not parked")
    func unresolvedNamedTitleIsMovable() {
        let item = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "at.obdev.littlesnitch.agent"),
            windowID: 104,
            sourcePID: nil
        )
        #expect(item.immovabilityReason == nil)
        #expect(item.isMovable)
    }

    /// Each gate must be distinguishable by its log text alone.
    @Test("The gates log distinct, non-empty descriptions")
    func logDescriptionsAreDistinct() {
        let prohibited = MenuBarItem.ImmovabilityReason.prohibitedSystemItem.logDescription
        let unresolved = MenuBarItem.ImmovabilityReason.unresolvedControlCenterPlaceholder.logDescription
        #expect(!prohibited.isEmpty)
        #expect(!unresolved.isEmpty)
        #expect(prohibited != unresolved)
        #expect(unresolved.contains("unresolved"))
    }
}
