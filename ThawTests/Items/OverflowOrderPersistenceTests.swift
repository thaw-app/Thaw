//
//  OverflowOrderPersistenceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Automatic overflow is presentation, not a layout edit. A profile or saved
/// order captured while the bar was tight must keep an authored-Visible item
/// in its Visible slot instead of recording it as Hidden.
@MainActor
@Suite("Overflow order persistence")
struct OverflowOrderPersistenceTests {
    private static func item(_ title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: UInt32(x) + 1,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    private static func transientItem(_ title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: title, instanceIndex: 0),
            windowID: UInt32(x) + 1,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    /// The same authored state the live section controller would supply.
    private static func source(
        order: [String],
        assignment: [String: MenuBarSectionName] = [:]
    ) -> MenuBarItemManager.AuthoredLayoutSource {
        MenuBarItemManager.AuthoredLayoutSource(
            sectionAssignment: assignment,
            sectionItemOrder: [.visible: order]
        )
    }

    @Test("An overflowed Visible item keeps its Visible slot in the persisted order")
    func overflowedVisibleItemKeepsItsSlot() {
        let a = Self.item("A", x: 10)
        let b = Self.item("B", x: 40)
        let c = Self.item("C", x: 70)
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [a, c]
        manager.itemCache[.hidden] = [b]
        manager.savedSectionOrder = [MenuBarSectionName.visible.rawValue: [a, b, c].map(\.uniqueIdentifier)]
        manager.authoredLayoutSourceOverride = Self.source(order: [a, b, c].map(\.uniqueIdentifier))

        let order = manager.computeSectionOrder(from: manager.itemCache)

        #expect(order[MenuBarSectionName.visible.rawValue] == [a, b, c].map(\.uniqueIdentifier))
        #expect(order[MenuBarSectionName.hidden.rawValue] == nil)
    }

    @Test("Multiple overflowed Visible items reinsert at their recorded slots")
    func multipleOverflowedItemsKeepTheirSlots() {
        let a = Self.item("A", x: 10)
        let b = Self.item("B", x: 40)
        let c = Self.item("C", x: 70)
        let d = Self.item("D", x: 100)
        let e = Self.item("E", x: 130)
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [a, c, e]
        manager.itemCache[.hidden] = [b, d]
        manager.authoredLayoutSourceOverride = Self.source(order: [a, b, c, d, e].map(\.uniqueIdentifier))

        let order = manager.computeSectionOrder(from: manager.itemCache)

        #expect(order[MenuBarSectionName.visible.rawValue] == [a, b, c, d, e].map(\.uniqueIdentifier))
    }

    @Test("A truly authored-Hidden item stays Hidden")
    func authoredHiddenItemStaysHidden() {
        let a = Self.item("A", x: 10)
        let b = Self.item("B", x: 40)
        let c = Self.item("C", x: 70)
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [a, c]
        manager.itemCache[.hidden] = [b]
        manager.authoredLayoutSourceOverride = Self.source(
            order: [a, c].map(\.uniqueIdentifier),
            assignment: [b.uniqueIdentifier: .hidden]
        )

        let order = manager.computeSectionOrder(from: manager.itemCache)

        #expect(order[MenuBarSectionName.visible.rawValue] == [a, c].map(\.uniqueIdentifier))
        #expect(order[MenuBarSectionName.hidden.rawValue] == [b.uniqueIdentifier])
    }

    @Test("An explicitly hidden former overflow item persists Hidden")
    func explicitlyHiddenFormerOverflowPersistsHidden() {
        let a = Self.item("A", x: 10)
        let b = Self.item("B", x: 40)
        let c = Self.item("C", x: 70)
        let d = Self.item("D", x: 100)
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [a, c]
        manager.itemCache[.hidden] = [b, d]
        manager.savedSectionOrder = [MenuBarSectionName.visible.rawValue: [a, b, c].map(\.uniqueIdentifier)]
        manager.authoredLayoutSourceOverride = Self.source(
            order: [a, c, d].map(\.uniqueIdentifier),
            assignment: [b.uniqueIdentifier: .hidden]
        )

        let order = manager.computeSectionOrder(from: manager.itemCache)

        #expect(order[MenuBarSectionName.visible.rawValue] == [a, c, d].map(\.uniqueIdentifier))
        #expect(order[MenuBarSectionName.hidden.rawValue] == [b.uniqueIdentifier])
    }

    @Test("An always-hidden item stays in the backend's bucket while Visible overflow is projected")
    func alwaysHiddenMembershipFollowsBackendBucket() {
        let a = Self.item("A", x: 10)
        let b = Self.item("B", x: 40)
        let alwaysHidden = Self.item("AH", x: 70)
        let manager = MenuBarItemManager()
        // allowsAlwaysHidden == false: the backend filed AH under Hidden.
        manager.itemCache[.visible] = [a]
        manager.itemCache[.hidden] = [alwaysHidden, b]
        manager.authoredLayoutSourceOverride = Self.source(
            order: [a, b].map(\.uniqueIdentifier),
            assignment: [alwaysHidden.uniqueIdentifier: .alwaysHidden]
        )

        let order = manager.computeSectionOrder(from: manager.itemCache)

        #expect(order[MenuBarSectionName.visible.rawValue] == [a, b].map(\.uniqueIdentifier))
        #expect(order[MenuBarSectionName.hidden.rawValue] == [alwaysHidden.uniqueIdentifier])
        #expect(order[MenuBarSectionName.alwaysHidden.rawValue] == nil)
    }

    @Test("A closed app keeps its slot while a Visible item is overflowed")
    func closedAppSlotSurvivesAlongsideOverflow() {
        let a = Self.item("A", x: 10)
        let b = Self.item("B", x: 40)
        let c = Self.item("C", x: 70)
        let closed = Self.item("Closed", x: 0).uniqueIdentifier
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [a, c]
        manager.itemCache[.hidden] = [b]
        manager.savedSectionOrder = [
            MenuBarSectionName.visible.rawValue: [a.uniqueIdentifier, b.uniqueIdentifier, closed, c.uniqueIdentifier],
        ]
        manager.authoredLayoutSourceOverride = Self.source(
            order: [a.uniqueIdentifier, b.uniqueIdentifier, closed, c.uniqueIdentifier]
        )

        let order = manager.computeSectionOrder(from: manager.itemCache)

        #expect(order[MenuBarSectionName.visible.rawValue] == [a.uniqueIdentifier, b.uniqueIdentifier, closed, c.uniqueIdentifier])
    }

    @Test("Transient Control Center widgets stay out of the projected order")
    func transientWidgetsStayExcluded() {
        let a = Self.item("A", x: 10)
        let transient = Self.transientItem("Item-0", x: 40)
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [a, transient]
        manager.authoredLayoutSourceOverride = Self.source(
            order: [a.uniqueIdentifier, transient.uniqueIdentifier]
        )

        let order = manager.computeSectionOrder(from: manager.itemCache)

        #expect(order[MenuBarSectionName.visible.rawValue] == [a.uniqueIdentifier])
    }

    @Test("Clearing overflow restores presentation without changing saved layout")
    func clearingOverflowLeavesSavedLayoutUnchanged() {
        let a = Self.item("A", x: 10)
        let b = Self.item("B", x: 40)
        let c = Self.item("C", x: 70)
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [a, b, c]
        manager.authoredLayoutSourceOverride = Self.source(order: [a, b, c].map(\.uniqueIdentifier))

        let order = manager.computeSectionOrder(from: manager.itemCache)

        #expect(order[MenuBarSectionName.visible.rawValue] == [a, b, c].map(\.uniqueIdentifier))
    }

    @Test("A stale cache after overflow clears still keeps the item Visible")
    func staleCacheAfterOverflowClearKeepsItemVisible() {
        // The controller has already cleared its overflow set, but the
        // effective cache still files B under Hidden until the next inventory
        // walk. A profile capture in that window must not record B as Hidden.
        let a = Self.item("A", x: 10)
        let b = Self.item("B", x: 40)
        let c = Self.item("C", x: 70)
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [a, c]
        manager.itemCache[.hidden] = [b]
        manager.savedSectionOrder = [MenuBarSectionName.visible.rawValue: [a, b, c].map(\.uniqueIdentifier)]
        manager.authoredLayoutSourceOverride = Self.source(order: [a, b, c].map(\.uniqueIdentifier))

        let order = manager.computeSectionOrder(from: manager.itemCache)

        #expect(order[MenuBarSectionName.visible.rawValue] == [a, b, c].map(\.uniqueIdentifier))
        #expect(order[MenuBarSectionName.hidden.rawValue] == nil)
    }

    @Test("Within-section reordering survives while another item is overflowed")
    func withinSectionReorderPreservedWhileOverflowConceals() {
        let a = Self.item("A", x: 10)
        let b = Self.item("B", x: 40)
        let c = Self.item("C", x: 70)
        let manager = MenuBarItemManager()
        // The user command-dragged C ahead of A; B is still overflowed.
        manager.itemCache[.visible] = [c, a]
        manager.itemCache[.hidden] = [b]
        manager.authoredLayoutSourceOverride = Self.source(order: [a, b, c].map(\.uniqueIdentifier))

        let order = manager.computeSectionOrder(from: manager.itemCache)

        // The live order [C, A] is the authority; B reinserts behind its
        // surviving recorded predecessor A.
        #expect(order[MenuBarSectionName.visible.rawValue] == [c, a, b].map(\.uniqueIdentifier))
    }

    @Test("A runtime whose cache agrees with its assignment uses legacy semantics")
    func runtimeWithAgreeingCacheKeepsLegacySemantics() {
        let a = Self.item("A", x: 10)
        let c = Self.item("C", x: 70)
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [a, c]
        manager.authoredLayoutSourceOverride = Self.source(order: [a, c].map(\.uniqueIdentifier))

        let order = manager.computeSectionOrder(from: manager.itemCache)

        #expect(order[MenuBarSectionName.visible.rawValue] == [a, c].map(\.uniqueIdentifier))
        #expect(order[MenuBarSectionName.hidden.rawValue] == nil)
    }

    @Test("Repeated capture is idempotent and leaves the presentation cache untouched")
    func repeatedCaptureIsIdempotent() {
        let a = Self.item("A", x: 10)
        let b = Self.item("B", x: 40)
        let c = Self.item("C", x: 70)
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [a, c]
        manager.itemCache[.hidden] = [b]
        let before = manager.itemCache
        manager.authoredLayoutSourceOverride = Self.source(order: [a, b, c].map(\.uniqueIdentifier))

        let first = manager.computeSectionOrder(from: manager.itemCache)
        let second = manager.computeSectionOrder(from: manager.itemCache)

        #expect(first == second)
        #expect(manager.itemCache == before)
    }

    @Test("No runtime keeps the effective cache as authority")
    func noRuntimeKeepsLegacySemantics() {
        let a = Self.item("A", x: 10)
        let b = Self.item("B", x: 40)
        let c = Self.item("C", x: 70)
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [a, c]
        manager.itemCache[.hidden] = [b]

        let order = manager.computeSectionOrder(from: manager.itemCache)

        #expect(order[MenuBarSectionName.visible.rawValue] == [a, c].map(\.uniqueIdentifier))
        #expect(order[MenuBarSectionName.hidden.rawValue] == [b.uniqueIdentifier])
    }

    @Test("Canonical identifiers from the record match live item identifiers")
    func canonicalIdentifiersMatchRecord() {
        // Dato's volatile title is canonicalized before use as identity.
        let item = MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.sindresorhus.Dato"), title: "Sat 3:41", instanceIndex: 0),
            windowID: 1,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: 10, y: 0, width: 24, height: 24),
            title: "Sat 3:41",
            isOnScreen: true
        )
        #expect(MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier) == item.uniqueIdentifier)
    }
}
