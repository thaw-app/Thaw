//
//  MenuBarAgentIdentityReconcilerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
@testable import MenuBarModel
import Testing

/// Walks inside a reveal window read MenuBarAgent extras without identifiers;
/// the reconciler carries the previous walk's identities forward across it.
@Suite("MenuBarAgent identity reconciliation")
struct MenuBarAgentIdentityReconcilerTests {
    /// An identified extra as the stable walk publishes it.
    private static func extra(
        _ identifier: String,
        x: CGFloat,
        width: CGFloat
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: identifier),
            windowID: UInt32(x),
            ownerPID: 665,
            sourcePID: nil,
            bounds: CGRect(x: x, y: 0, width: width, height: 30),
            title: nil,
            isOnScreen: true
        )
    }

    /// The same slot as a transition walk sees it: no naming attributes, so
    /// the walk minted a positional identity.
    private static func unnamed(
        index: Int,
        x: CGFloat,
        width: CGFloat,
        windowID: UInt32 = 999
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "Item-\(index)"),
            windowID: windowID,
            ownerPID: 665,
            sourcePID: nil,
            bounds: CGRect(x: x, y: 0, width: width, height: 30),
            title: nil,
            isOnScreen: true
        )
    }

    private static var identifiedBar: [MenuBarItem] {
        [
            extra("com.apple.menuextra.bluetooth", x: 2006, width: 16),
            extra("com.apple.menuextra.wifi", x: 2038, width: 22),
            extra("com.apple.menuextra.controlcenter", x: 2410, width: 26),
            extra("com.apple.menuextra.clock", x: 2483, width: 57),
        ]
    }

    @Test("An unnamed extra adopts the identified tag of the slot it occupies")
    func unnamedAdoptsPreviousIdentity() {
        let fresh = [
            Self.unnamed(index: 1, x: 2006, width: 16),
            Self.unnamed(index: 2, x: 2038, width: 22),
        ]
        let result = MenuBarAgentIdentityReconciler.reconcile(fresh: fresh, previous: Self.identifiedBar)
        #expect(result.restoredCount == 2)
        #expect(result.items[0].tag == MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.bluetooth"))
        #expect(result.items[1].tag == MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.wifi"))
    }

    @Test("Fresh geometry survives the identity carry-forward")
    func geometryStaysFresh() {
        let fresh = [Self.unnamed(index: 3, x: 2410, width: 26, windowID: 777)]
        let result = MenuBarAgentIdentityReconciler.reconcile(fresh: fresh, previous: Self.identifiedBar)
        #expect(result.items[0].tag.title == "com.apple.menuextra.controlcenter")
        #expect(result.items[0].windowID == 777)
        #expect(result.items[0].bounds == fresh[0].bounds)
    }

    @Test("Identified fresh items pass through untouched")
    func identifiedItemsUntouched() {
        let result = MenuBarAgentIdentityReconciler.reconcile(fresh: Self.identifiedBar, previous: Self.identifiedBar)
        #expect(result.restoredCount == 0)
        #expect(result.items.map(\.tag) == Self.identifiedBar.map(\.tag))
        #expect(result.items.map(\.bounds) == Self.identifiedBar.map(\.bounds))
    }

    @Test("A slot beyond the tolerance is left unnamed rather than misidentified")
    func beyondToleranceNoMerge() {
        // 40 pt away from every identified slot: a genuinely new extra.
        let fresh = [Self.unnamed(index: 0, x: 2100, width: 20)]
        let result = MenuBarAgentIdentityReconciler.reconcile(fresh: fresh, previous: Self.identifiedBar)
        #expect(result.restoredCount == 0)
        #expect(result.items[0].tag.title == "Item-0")
    }

    @Test("Each identified slot is carried forward at most once")
    func slotsAreConsumedOnce() {
        // Two unnamed items near one identified slot: the nearer wins, the
        // other has no honest identity to take and stays unnamed.
        let fresh = [
            Self.unnamed(index: 0, x: 2037, width: 22),
            Self.unnamed(index: 1, x: 2041, width: 22),
        ]
        let result = MenuBarAgentIdentityReconciler.reconcile(fresh: fresh, previous: Self.identifiedBar)
        #expect(result.restoredCount == 1)
        #expect(result.items[0].tag.title == "com.apple.menuextra.wifi")
        #expect(result.items[1].tag.title == "Item-1")
    }

    @Test("A positional previous item is never a source identity")
    func positionalPreviousNeverSubstitutes() {
        // The previous walk was itself degraded; carrying its names forward
        // would launder the degradation into a permanent identity.
        let degraded: [MenuBarItem] = [
            Self.unnamed(index: 0, x: 2006, width: 16),
            Self.unnamed(index: 2, x: 2038, width: 22),
        ]
        let fresh = [Self.unnamed(index: 5, x: 2038, width: 22)]
        let result = MenuBarAgentIdentityReconciler.reconcile(fresh: fresh, previous: degraded)
        #expect(result.restoredCount == 0)
        #expect(result.items[0].tag.title == "Item-5")
    }

    @Test("Non-hosting namespaces are never touched")
    func thirdPartyItemsUntouched() {
        let thirdParty = MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.raycast.macos"), title: "Item-0"),
            windowID: 1,
            ownerPID: 4345,
            sourcePID: nil,
            bounds: CGRect(x: 1627, y: 0, width: 34, height: 30),
            title: nil,
            isOnScreen: true
        )
        let result = MenuBarAgentIdentityReconciler.reconcile(fresh: [thirdParty], previous: Self.identifiedBar)
        #expect(result.restoredCount == 0)
        #expect(result.items[0].tag == thirdParty.tag)
    }

    @Test("An empty previous walk is a no-op, not a cold-start hazard")
    func emptyPreviousIsNoOp() {
        let fresh = [Self.unnamed(index: 0, x: 2006, width: 16)]
        let result = MenuBarAgentIdentityReconciler.reconcile(fresh: fresh, previous: [])
        #expect(result.restoredCount == 0)
        #expect(result.items.map(\.tag) == fresh.map(\.tag))
    }

    @Test("A departed extra is not resurrected by an unrelated arrival")
    func departureStillReadsAsDeparture() {
        // Wi-Fi genuinely left the bar; a new unnamed extra appeared in
        // Control Center's old slot. The merge substitutes by slot, so the
        // arrival reads as control center, never as wifi returning.
        var withoutWiFi = Self.identifiedBar
        withoutWiFi.removeAll { $0.tag.title == "com.apple.menuextra.wifi" }
        let fresh = [
            Self.extra("com.apple.menuextra.bluetooth", x: 2006, width: 16),
            Self.unnamed(index: 9, x: 2038, width: 22),
        ]
        let result = MenuBarAgentIdentityReconciler.reconcile(fresh: fresh, previous: withoutWiFi)
        #expect(result.restoredCount == 0)
        #expect(result.items[1].tag.title == "Item-9")
    }

    // MARK: Stateful front

    @Suite(.serialized)
    struct Stateful {
        init() {
            MenuBarAgentIdentityReconciler.resetState()
        }

        @Test("A degraded walk after an identified one restores identities")
        func degradedAfterIdentifiedRestores() {
            _ = MenuBarAgentIdentityReconciler.reconciling(MenuBarAgentIdentityReconcilerTests.identifiedBar)
            let fresh = [
                MenuBarAgentIdentityReconcilerTests.unnamed(index: 0, x: 2006, width: 16),
                MenuBarAgentIdentityReconcilerTests.unnamed(index: 1, x: 2038, width: 22),
            ]
            let result = MenuBarAgentIdentityReconciler.reconciling(fresh)
            #expect(result.restoredCount == 2)
            #expect(result.items[0].tag.title == "com.apple.menuextra.bluetooth")
        }

        @Test("A zero-item transition walk does not erase the memory")
        func zeroItemWalkKeepsSnapshot() {
            _ = MenuBarAgentIdentityReconciler.reconciling(MenuBarAgentIdentityReconcilerTests.identifiedBar)
            _ = MenuBarAgentIdentityReconciler.reconciling([])
            let fresh = [MenuBarAgentIdentityReconcilerTests.unnamed(index: 3, x: 2410, width: 26)]
            let result = MenuBarAgentIdentityReconciler.reconciling(fresh)
            #expect(result.restoredCount == 1)
            #expect(result.items[0].tag.title == "com.apple.menuextra.controlcenter")
        }

        @Test("A fully degraded walk does not overwrite the snapshot")
        func degradedWalkDoesNotOverwriteSnapshot() {
            _ = MenuBarAgentIdentityReconciler.reconciling(MenuBarAgentIdentityReconcilerTests.identifiedBar)
            // An identified extra departed and two strangers arrived: nothing
            // merges, so the snapshot must keep the earlier bar.
            let strangers = [
                MenuBarAgentIdentityReconcilerTests.unnamed(index: 0, x: 100, width: 20),
                MenuBarAgentIdentityReconcilerTests.unnamed(index: 1, x: 300, width: 20),
            ]
            _ = MenuBarAgentIdentityReconciler.reconciling(strangers)
            let fresh = [MenuBarAgentIdentityReconcilerTests.unnamed(index: 2, x: 2038, width: 22)]
            let result = MenuBarAgentIdentityReconciler.reconciling(fresh)
            #expect(result.restoredCount == 1)
            #expect(result.items[0].tag.title == "com.apple.menuextra.wifi")
        }
    }
}
