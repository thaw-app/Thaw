//
//  ImmovabilityReasonTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Characterizes the gate that refuses to move an item, and its agreement
/// with `isMovable`.
///
/// The refusal used to be silent: the layout editor showed a generic alert
/// naming the item's fallback display name, nothing was logged, and #905's
/// reporter could not tell a static macOS prohibition from an
/// identity-resolution failure. The named reason is what the refusal sites
/// log and what the alert copy branches on, so each gate is pinned here.
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

    /// The #905 case: a generic Control Center slot whose source process
    /// never resolved. The owning app is unknown, so the item is parked.
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

    /// A named (non-generic) Control Center hosted title is not gated by
    /// the placeholder rule even while its source is unresolved — only the
    /// `Item-N` shape marks a system-owned slot.
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

    /// The log line is the diagnostic #905 asked for, so each gate has to
    /// stay tellable from the other by its text alone.
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
